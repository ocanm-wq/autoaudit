-- Cargar 00_comun.sql antes, en la misma conexión. Las semillas NO prueban triggers.
BEGIN;
SELECT pg_temp.aa_guard();
CREATE TABLE public.aa_funcional(id integer PRIMARY KEY,nombre text,correo text,telefono text);
CREATE TABLE public.aa_sentinel(id integer PRIMARY KEY);
SELECT pg_temp.aa_check('catalogo_eventos',(SELECT array_agg(nombre::text ORDER BY id_evento)=ARRAY['INSERT','UPDATE','DELETE'] FROM auditoria.aud_evento));
SELECT pg_temp.aa_error('evento_check','INSERT INTO auditoria.aud_evento VALUES (9,''OTRO'')',ARRAY['23514']);
SELECT pg_temp.aa_error('evento_unique','INSERT INTO auditoria.aud_evento VALUES (1,''INSERT'')',ARRAY['23505']);
INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES ('public','aa_funcional');
INSERT INTO auditoria.aud_columna(id_tabla,nombre_columna)
 SELECT id_tabla,c FROM auditoria.aud_tabla CROSS JOIN unnest(ARRAY['nombre','correo']) c WHERE nombre_tabla='aa_funcional' AND esquema='public';
INSERT INTO auditoria.aud_configuracion(id_columna,id_evento)
 SELECT col.id_columna,e.id_evento FROM auditoria.aud_columna col JOIN auditoria.aud_tabla t USING(id_tabla)
 CROSS JOIN auditoria.aud_evento e WHERE t.nombre_tabla='aa_funcional' AND t.esquema='public';
SELECT pg_temp.aa_error('tabla_unique','INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES (''public'',''aa_funcional'')',ARRAY['23505']);
SELECT pg_temp.aa_error('columna_fk','INSERT INTO auditoria.aud_columna(id_tabla,nombre_columna) VALUES (-1,''x'')',ARRAY['23503']);
SELECT pg_temp.aa_error('config_fk_columna','INSERT INTO auditoria.aud_configuracion(id_columna,id_evento) VALUES (-1,1)',ARRAY['23503']);
SELECT pg_temp.aa_error('config_fk_evento','INSERT INTO auditoria.aud_configuracion(id_columna,id_evento) SELECT min(id_columna),9 FROM auditoria.aud_columna',ARRAY['23503']);
SELECT pg_temp.aa_error('config_not_null','INSERT INTO auditoria.aud_configuracion(id_columna,id_evento) VALUES (NULL,1)',ARRAY['23502']);
SELECT pg_temp.aa_error('config_unique','INSERT INTO auditoria.aud_configuracion(id_columna,id_evento) SELECT id_columna,id_evento FROM auditoria.aud_configuracion LIMIT 1',ARRAY['23505']);

-- Fixtures de historial insertados explícitamente por el dueño para probar 05.
INSERT INTO auditoria.aud_usuario(nombre_usuario) VALUES ('aa_fixture_uno'),('aa_fixture_otro');
INSERT INTO auditoria.aud_estacion(ip_origen,nombre_host) VALUES ('127.0.0.1','aa-fixture');
CREATE TEMP TABLE aa_esperado(columna text,evento text,id_registro text,valor_anterior text,valor_nuevo text);
INSERT INTO aa_esperado VALUES
 ('nombre','INSERT','9001',NULL,'Ana'),('correo','INSERT','9001',NULL,'a@ejemplo.test'),
 ('correo','UPDATE','9001','a@ejemplo.test','b@ejemplo.test'),
 ('nombre','DELETE','9001','Ana',NULL),('correo','DELETE','9001','b@ejemplo.test',NULL);
INSERT INTO auditoria.aud_bitacora(id_configuracion,id_usuario,id_estacion,fecha_hora,id_registro,valor_anterior,valor_nuevo)
 SELECT cf.id_configuracion,u.id_usuario,s.id_estacion,transaction_timestamp()-interval '1 hour',x.id_registro,x.valor_anterior,x.valor_nuevo
 FROM aa_esperado x JOIN auditoria.aud_columna col ON col.nombre_columna=x.columna
 JOIN auditoria.aud_tabla t ON t.id_tabla=col.id_tabla AND t.nombre_tabla='aa_funcional' AND t.esquema='public'
 JOIN auditoria.aud_configuracion cf ON cf.id_columna=col.id_columna
 JOIN auditoria.aud_evento ev ON ev.id_evento=cf.id_evento AND ev.nombre=x.evento
 CROSS JOIN auditoria.aud_usuario u CROSS JOIN auditoria.aud_estacion s
 WHERE u.nombre_usuario='aa_fixture_uno' AND s.nombre_host='aa-fixture';
INSERT INTO auditoria.aud_bitacora(id_configuracion,id_usuario,id_estacion,id_registro,valor_nuevo)
 SELECT cf.id_configuracion,u.id_usuario,s.id_estacion,'9002','Otro'
 FROM auditoria.aud_configuracion cf JOIN auditoria.aud_columna col USING(id_columna) JOIN auditoria.aud_tabla t USING(id_tabla)
 CROSS JOIN auditoria.aud_usuario u CROSS JOIN auditoria.aud_estacion s
 WHERE t.nombre_tabla='aa_funcional' AND col.nombre_columna='nombre' AND cf.id_evento=1 AND u.nombre_usuario='aa_fixture_otro' AND s.nombre_host='aa-fixture';
DO $$ DECLARE f text; q text; ok boolean; casos text[]:=ARRAY['consulta_usuario','consulta_columna','consulta_registro']; i int;
BEGIN
 FOR i IN 1..3 LOOP
  f:=CASE i WHEN 1 THEN 'auditoria.historial_por_usuario(text,timestamp with time zone,timestamp with time zone)'
   WHEN 2 THEN 'auditoria.historial_por_columna(text,text,text,timestamp with time zone,timestamp with time zone)'
   ELSE 'auditoria.historial_por_registro(text,text,text)' END;
  IF to_regprocedure(f) IS NULL THEN PERFORM pg_temp.aa_skip(casos[i],'Falta función: revisar 05'); CONTINUE; END IF;
  q:=CASE i WHEN 1 THEN 'SELECT columna::text,evento::text,id_registro,valor_anterior,valor_nuevo FROM auditoria.historial_por_usuario(''aa_fixture_uno'')'
   WHEN 2 THEN 'SELECT columna::text,evento::text,id_registro,valor_anterior,valor_nuevo FROM auditoria.historial_por_columna(''public'',''aa_funcional'',''correo'')'
   ELSE 'SELECT columna::text,evento::text,id_registro,valor_anterior,valor_nuevo FROM auditoria.historial_por_registro(''public'',''aa_funcional'',''9001'')' END;
  BEGIN
   EXECUTE 'WITH esperado AS (SELECT * FROM aa_esperado'||CASE WHEN i=2 THEN ' WHERE columna=''correo''' ELSE '' END||'), real AS ('||q||') SELECT NOT EXISTS ((TABLE real EXCEPT ALL TABLE esperado) UNION ALL (TABLE esperado EXCEPT ALL TABLE real))' INTO ok;
   PERFORM pg_temp.aa_check(casos[i],ok,'Multiset exacto en ambas direcciones; fixtures');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.aa_check(casos[i],false,SQLSTATE||' '||SQLERRM); END;
 END LOOP;
 IF to_regprocedure('auditoria.historial_por_usuario(text,timestamp with time zone,timestamp with time zone)') IS NOT NULL THEN
  PERFORM pg_temp.aa_check('consulta_limites_temporales',
   (SELECT count(*)=5 FROM auditoria.historial_por_usuario('aa_fixture_uno',transaction_timestamp()-interval '1 hour',transaction_timestamp()))
   AND (SELECT count(*)=0 FROM auditoria.historial_por_usuario('aa_fixture_uno',NULL,transaction_timestamp()-interval '1 hour')),'desde inclusivo; hasta exclusivo');
 ELSE PERFORM pg_temp.aa_skip('consulta_limites_temporales','Falta función 05'); END IF;
 IF to_regprocedure('auditoria.historial_por_columna(text,text,text,timestamp with time zone,timestamp with time zone)') IS NOT NULL THEN
  PERFORM pg_temp.aa_check('consulta_objeto_invalido',(SELECT count(*)=0 FROM auditoria.historial_por_columna('aa_no_existe','x','y')),'Filtro inexistente devuelve conjunto vacío');
 ELSE PERFORM pg_temp.aa_skip('consulta_objeto_invalido','Falta función 05'); END IF;
END $$;

DO $$
DECLARE tabla_id int; n bigint; caso text; ok boolean; invalida int;
 casos text[]:=ARRAY['dml_multiset_exacto','dml_identidad_fecha','dml_eliminado_consultable','dml_null',
 'dml_regeneracion_sin_duplicados','dml_update_sin_cambio','dml_no_auditada','generador_tabla_invalida',
 'generador_columna_invalida','generador_config_id_invalido','generador_inyeccion',
 'config_desactivada','tabla_desactivada'];
BEGIN
 IF to_regprocedure('auditoria.generar_trigger(integer)') IS NULL THEN
  FOREACH caso IN ARRAY casos LOOP PERFORM pg_temp.aa_skip(caso,'03 vacío: falta generador real'); END LOOP;
  RETURN;
 END IF;
 SELECT id_tabla INTO tabla_id FROM auditoria.aud_tabla WHERE esquema='public' AND nombre_tabla='aa_funcional';
 BEGIN
  PERFORM auditoria.generar_trigger(tabla_id);
  INSERT INTO public.aa_funcional VALUES (3,'Marta','marta0@ejemplo.test','5555');
  UPDATE public.aa_funcional SET correo='marta1@ejemplo.test' WHERE id=3;
  DELETE FROM public.aa_funcional WHERE id=3;
  WITH esperado(columna,evento,id_registro,valor_anterior,valor_nuevo) AS (VALUES
   ('nombre','INSERT','3',NULL::text,'Marta'),('correo','INSERT','3',NULL,'marta0@ejemplo.test'),
   ('correo','UPDATE','3','marta0@ejemplo.test','marta1@ejemplo.test'),('nombre','DELETE','3','Marta',NULL),('correo','DELETE','3','marta1@ejemplo.test',NULL)),
  real AS (SELECT columna::text,evento::text,id_registro,valor_anterior,valor_nuevo FROM auditoria.v_historial
   WHERE esquema='public' AND tabla='aa_funcional' AND id_registro='3')
  SELECT NOT EXISTS ((TABLE real EXCEPT ALL TABLE esperado) UNION ALL (TABLE esperado EXCEPT ALL TABLE real)) INTO ok;
  PERFORM pg_temp.aa_check('dml_multiset_exacto',ok,'INSERT=2 UPDATE=1 DELETE=2; OLD/NEW/id/columna/evento exactos');
  PERFORM pg_temp.aa_check('dml_identidad_fecha',
   (SELECT count(*)=5 AND bool_and(usuario=current_user AND fecha_hora>=transaction_timestamp() AND fecha_hora<=clock_timestamp())
    FROM auditoria.v_historial WHERE esquema='public' AND tabla='aa_funcional' AND id_registro='3'),'Usuario dueño y fecha dentro de transacción');
  IF to_regprocedure('auditoria.historial_por_registro(text,text,text)') IS NULL THEN PERFORM pg_temp.aa_skip('dml_eliminado_consultable','Falta consulta 05');
  ELSE PERFORM pg_temp.aa_check('dml_eliminado_consultable',NOT EXISTS(SELECT FROM public.aa_funcional WHERE id=3)
    AND (SELECT count(*)=5 FROM auditoria.historial_por_registro('public','aa_funcional','3'))); END IF;
  INSERT INTO public.aa_funcional VALUES(4,'Nora','x','5555');
  UPDATE public.aa_funcional SET correo=NULL WHERE id=4;
  UPDATE public.aa_funcional SET correo='y' WHERE id=4;
  PERFORM pg_temp.aa_check('dml_null',
   (SELECT count(*)=1 FROM auditoria.v_historial WHERE tabla='aa_funcional' AND id_registro='4' AND columna='correo' AND evento='UPDATE' AND valor_anterior='x' AND valor_nuevo IS NULL)
   AND (SELECT count(*)=1 FROM auditoria.v_historial WHERE tabla='aa_funcional' AND id_registro='4' AND columna='correo' AND evento='UPDATE' AND valor_anterior IS NULL AND valor_nuevo='y'));
  PERFORM auditoria.generar_trigger(tabla_id); PERFORM auditoria.generar_trigger(tabla_id);
  SELECT count(*) INTO n FROM auditoria.v_historial WHERE tabla='aa_funcional';
  INSERT INTO public.aa_funcional VALUES(5,'Sol','s','5555');
  PERFORM pg_temp.aa_check('dml_regeneracion_sin_duplicados',
   (SELECT count(*)=1 FROM pg_trigger WHERE tgrelid='public.aa_funcional'::regclass AND NOT tgisinternal)
   AND (SELECT count(*)=n+2 FROM auditoria.v_historial WHERE tabla='aa_funcional'));
  SELECT count(*) INTO n FROM auditoria.v_historial WHERE tabla='aa_funcional';
  UPDATE public.aa_funcional SET nombre=nombre WHERE id=5;
  PERFORM pg_temp.aa_check('dml_update_sin_cambio',(SELECT count(*)=n FROM auditoria.v_historial WHERE tabla='aa_funcional'));
  UPDATE public.aa_funcional SET telefono='nuevo' WHERE id=5;
  PERFORM pg_temp.aa_check('dml_no_auditada',(SELECT count(*)=n FROM auditoria.v_historial WHERE tabla='aa_funcional'));
  UPDATE auditoria.aud_configuracion cf SET activa=false FROM auditoria.aud_columna c
    WHERE c.id_columna=cf.id_columna AND c.id_tabla=tabla_id AND c.nombre_columna='correo' AND cf.id_evento=2;
  PERFORM auditoria.generar_trigger(tabla_id); UPDATE public.aa_funcional SET correo='sin-evento' WHERE id=5;
  PERFORM pg_temp.aa_check('config_desactivada',(SELECT count(*)=n FROM auditoria.v_historial WHERE tabla='aa_funcional'));
  UPDATE auditoria.aud_tabla SET activa=false WHERE id_tabla=tabla_id;
  PERFORM auditoria.generar_trigger(tabla_id); UPDATE public.aa_funcional SET nombre='sin-auditoria' WHERE id=5;
  PERFORM pg_temp.aa_check('tabla_desactivada',(SELECT count(*)=n FROM auditoria.v_historial WHERE tabla='aa_funcional'));
 EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.aa_check('dml_ejecucion',false,SQLSTATE||' '||SQLERRM);
  FOREACH caso IN ARRAY casos[1:7]||casos[12:13] LOOP
   IF NOT EXISTS(SELECT FROM pg_temp.aa_results WHERE id=caso) THEN PERFORM pg_temp.aa_skip(caso,'DML abortado: ver dml_ejecucion'); END IF;
  END LOOP;
 END;
 PERFORM pg_temp.aa_error('generador_config_id_invalido','SELECT auditoria.generar_trigger(-1)',ARRAY['P0001','22023']);
 INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES('aa_no_existe','x') RETURNING id_tabla INTO invalida;
 PERFORM pg_temp.aa_error('generador_tabla_invalida',format('SELECT auditoria.generar_trigger(%s)',invalida),ARRAY['42P01','3F000','P0001','22023']);
 INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES('public','aa_sentinel') RETURNING id_tabla INTO invalida;
 INSERT INTO auditoria.aud_columna(id_tabla,nombre_columna) VALUES(invalida,'aa_no_columna');
 INSERT INTO auditoria.aud_configuracion(id_columna,id_evento) SELECT id_columna,1 FROM auditoria.aud_columna WHERE id_tabla=invalida;
 PERFORM pg_temp.aa_error('generador_columna_invalida',format('SELECT auditoria.generar_trigger(%s)',invalida),ARRAY['42703','P0001','22023']);
 INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES('public','aa_x"; DROP TABLE public.aa_sentinel; --') RETURNING id_tabla INTO invalida;
 PERFORM pg_temp.aa_error('generador_inyeccion_rechazo',format('SELECT auditoria.generar_trigger(%s)',invalida),ARRAY['42P01','P0001','22023']);
 PERFORM pg_temp.aa_check('generador_inyeccion',to_regclass('public.aa_sentinel') IS NOT NULL,'Centinela conservado; falta revisión completa del código de 03');
END $$;
SELECT * FROM pg_temp.aa_report();
ROLLBACK;
