-- Ejecutar como dueño/superusuario SOLO en clúster dedicado de pruebas.
-- Puede validar los controles independientes extraídos de 06 sin simular 03.
BEGIN;
SELECT pg_temp.aa_guard();
DO $$
DECLARE r text; op text; sql_intento text; b bigint; c int; u int; e int; tabla_id int;
 caso text; ok boolean; f text; rol_owner text:=current_user;
BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='aud_admin')
 OR NOT EXISTS(SELECT FROM pg_roles WHERE rolname='aud_consulta')
 OR NOT EXISTS(SELECT FROM pg_trigger WHERE tgrelid='auditoria.aud_bitacora'::regclass AND tgname='trg_bitacora_inmutable') THEN
  FOREACH caso IN ARRAY ARRAY['roles_y_acl','admin_configuracion','consulta_configuracion','historial_autorizado',
    'admin_insert','admin_update','admin_delete','admin_truncate','consulta_insert','consulta_update','consulta_delete','consulta_truncate',
    'public_permisos','security_definer','propietario_limites'] LOOP
   PERFORM pg_temp.aa_skip(caso,'06 no instalado; usar diagnóstico independiente o integrar 03');
  END LOOP; RETURN;
 END IF;
 PERFORM pg_temp.aa_check('roles_sin_login',(SELECT count(*)=2 AND bool_and(NOT rolcanlogin AND NOT rolsuper AND NOT rolcreaterole)
    FROM pg_roles WHERE rolname IN('aud_admin','aud_consulta')));
 PERFORM pg_temp.aa_check('admin_hereda_consulta',pg_has_role('aud_admin','aud_consulta','USAGE'));
 PERFORM pg_temp.aa_check('roles_sin_create_esquema',NOT has_schema_privilege('aud_admin','auditoria','CREATE')
   AND NOT has_schema_privilege('aud_consulta','auditoria','CREATE'));
 CREATE TABLE public.aa_seguridad(id integer PRIMARY KEY);
 INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES('public','aa_seguridad');
 SELECT id_tabla INTO tabla_id FROM auditoria.aud_tabla WHERE esquema='public' AND nombre_tabla='aa_seguridad';
 INSERT INTO auditoria.aud_columna(id_tabla,nombre_columna)
   SELECT id_tabla,'id' FROM auditoria.aud_tabla WHERE esquema='public' AND nombre_tabla='aa_seguridad';
 INSERT INTO auditoria.aud_configuracion(id_columna,id_evento)
   SELECT col.id_columna,1 FROM auditoria.aud_columna col JOIN auditoria.aud_tabla t USING(id_tabla) WHERE t.nombre_tabla='aa_seguridad'
   RETURNING id_configuracion INTO c;
 INSERT INTO auditoria.aud_usuario(nombre_usuario) VALUES('aa_seguridad') RETURNING id_usuario INTO u;
 INSERT INTO auditoria.aud_estacion(ip_origen,nombre_host) VALUES('127.0.0.1','aa_seguridad') RETURNING id_estacion INTO e;
 INSERT INTO auditoria.aud_bitacora(id_configuracion,id_usuario,id_estacion,id_registro,valor_nuevo)
   VALUES(c,u,e,'7001','1') RETURNING id_bitacora INTO b;
 PERFORM pg_temp.aa_check('fixture_bitacora_existe',EXISTS(SELECT FROM auditoria.aud_bitacora WHERE id_bitacora=b));
 FOREACH r IN ARRAY ARRAY['aud_admin','aud_consulta'] LOOP
  FOREACH op IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE'] LOOP
   sql_intento:=CASE op
    WHEN 'INSERT' THEN format('INSERT INTO auditoria.aud_bitacora(id_configuracion,id_usuario,id_estacion,id_registro) VALUES(%s,%s,%s,''intruso'')',c,u,e)
    WHEN 'UPDATE' THEN format('UPDATE auditoria.aud_bitacora SET valor_nuevo=''intruso'' WHERE id_bitacora=%s',b)
    WHEN 'DELETE' THEN format('DELETE FROM auditoria.aud_bitacora WHERE id_bitacora=%s',b)
    ELSE 'TRUNCATE auditoria.aud_bitacora' END;
   PERFORM pg_temp.aa_as_role(r||'_'||lower(op),r,sql_intento,ARRAY['42501']);
  END LOOP;
  PERFORM pg_temp.aa_as_role(r||'_lectura_directa',r,'SELECT * FROM auditoria.aud_bitacora',ARRAY['42501']);
  PERFORM pg_temp.aa_as_role(r||'_vista',r,'SELECT count(*) FROM auditoria.v_historial WHERE tabla=''aa_seguridad''',ARRAY['00000'],'1');
  PERFORM pg_temp.aa_as_role(r||'_historial_usuario',r,'SELECT count(*) FROM auditoria.historial_por_usuario(''aa_seguridad'')',ARRAY['00000'],'1');
  PERFORM pg_temp.aa_as_role(r||'_historial_columna',r,'SELECT count(*) FROM auditoria.historial_por_columna(''public'',''aa_seguridad'',''id'')',ARRAY['00000'],'1');
  PERFORM pg_temp.aa_as_role(r||'_historial_registro',r,'SELECT count(*) FROM auditoria.historial_por_registro(''public'',''aa_seguridad'',''7001'')',ARRAY['00000'],'1');
 END LOOP;
 PERFORM pg_temp.aa_as_role('admin_config_insert','aud_admin','INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES(''public'',''aa_config'') RETURNING 1',ARRAY['00000'],'1');
 PERFORM pg_temp.aa_as_role('admin_config_update','aud_admin','UPDATE auditoria.aud_tabla SET activa=false WHERE nombre_tabla=''aa_seguridad'' RETURNING 1',ARRAY['00000'],'1');
 PERFORM pg_temp.aa_as_role('admin_config_delete_denegado','aud_admin','DELETE FROM auditoria.aud_tabla WHERE nombre_tabla=''aa_seguridad''',ARRAY['42501']);
 PERFORM pg_temp.aa_as_role('consulta_config_insert_denegado','aud_consulta','INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES(''public'',''aa_config'')',ARRAY['42501']);
 PERFORM pg_temp.aa_as_role('consulta_config_update_denegado','aud_consulta','UPDATE auditoria.aud_tabla SET activa=false WHERE nombre_tabla=''aa_seguridad''',ARRAY['42501']);
 -- PUBLIC es pseudo-rol (grantee=0); no usar has_*_privilege('public',...).
 PERFORM pg_temp.aa_check('public_schema_sin_usage',NOT EXISTS(
  SELECT FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
  WHERE n.nspname='auditoria' AND a.grantee=0 AND a.privilege_type IN('USAGE','CREATE')));
 PERFORM pg_temp.aa_check('public_tablas_sin_permisos',NOT EXISTS(
  SELECT FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace
  CROSS JOIN LATERAL aclexplode(coalesce(t.relacl,acldefault('r',t.relowner))) a
  WHERE n.nspname='auditoria' AND a.grantee=0));
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='aa_public_probe') THEN RAISE EXCEPTION 'Colisión rol aa_public_probe'; END IF;
 CREATE ROLE aa_public_probe NOLOGIN;
 PERFORM pg_temp.aa_as_role('public_probe_vista_denegado','aa_public_probe','SELECT * FROM auditoria.v_historial',ARRAY['42501']);
 PERFORM pg_temp.aa_as_role('public_probe_historial_denegado','aa_public_probe','SELECT * FROM auditoria.historial_por_usuario(''aa_seguridad'')',ARRAY['42501']);
 PERFORM pg_temp.aa_check('public_execute_funciones_actuales',NOT EXISTS(
  SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  WHERE n.nspname='auditoria' AND a.grantee=0 AND a.privilege_type='EXECUTE'),
  'Detecta función de bloqueo creada DESPUÉS de REVOKE ALL; sin USAGE no es acceso efectivo por sí solo');
 EXECUTE 'CREATE FUNCTION auditoria.aa_futura() RETURNS integer LANGUAGE sql AS ''SELECT 1''';
 PERFORM pg_temp.aa_check('public_execute_funciones_futuras',NOT has_function_privilege('aa_public_probe','auditoria.aa_futura()','EXECUTE'),
  'ALTER DEFAULT PRIVILEGES debe cubrir al propietario que crea las funciones');
 FOREACH f IN ARRAY ARRAY['generar_trigger','eliminar_trigger'] LOOP
  IF to_regprocedure('auditoria.'||f||'(integer)') IS NULL THEN
   PERFORM pg_temp.aa_skip(f||'_security_definer','03 vacío: función ausente');
   PERFORM pg_temp.aa_skip(f||'_execute_roles','03 vacío: función ausente');
   PERFORM pg_temp.aa_skip(f||'_admin_operacion_real','03 vacío: función ausente');
  ELSE
   PERFORM pg_temp.aa_check(f||'_security_definer',
    (SELECT prosecdef AND 'search_path=auditoria, pg_temp'=ANY(coalesce(proconfig,ARRAY[]::text[]))
     FROM pg_proc WHERE oid=to_regprocedure('auditoria.'||f||'(integer)')),'Revisar además propietario confiable y referencias calificadas');
   PERFORM pg_temp.aa_check(f||'_execute_roles',
     has_function_privilege('aud_admin','auditoria.'||f||'(integer)','EXECUTE')
     AND NOT has_function_privilege('aud_consulta','auditoria.'||f||'(integer)','EXECUTE')
     AND NOT has_function_privilege('aa_public_probe','auditoria.'||f||'(integer)','EXECUTE'));
   PERFORM pg_temp.aa_as_role(f||'_consulta_denegada','aud_consulta','SELECT auditoria.'||f||'(-1)',ARRAY['42501']);
   BEGIN
    IF f='eliminar_trigger' THEN PERFORM auditoria.generar_trigger(tabla_id); END IF;
    sql_intento:=format('DO $probe$ BEGIN PERFORM auditoria.%I(%s); IF %s EXISTS '
     ||'(SELECT FROM pg_trigger WHERE tgrelid=''public.aa_seguridad''::regclass AND NOT tgisinternal) '
     ||'THEN RAISE EXCEPTION ''Estado de trigger inesperado''; END IF; END $probe$;',
     f,tabla_id,CASE WHEN f='generar_trigger' THEN 'NOT' ELSE '' END);
    PERFORM pg_temp.aa_as_role(f||'_admin_operacion_real','aud_admin',sql_intento,ARRAY['00000']);
   EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.aa_check(f||'_admin_operacion_real',false,SQLSTATE||' '||SQLERRM);
   END;
  END IF;
 END LOOP;
 PERFORM pg_temp.aa_error('owner_update_bloqueado',format('UPDATE auditoria.aud_bitacora SET valor_nuevo=''intruso'' WHERE id_bitacora=%s',b),ARRAY['P0001']);
 PERFORM pg_temp.aa_error('owner_delete_bloqueado',format('DELETE FROM auditoria.aud_bitacora WHERE id_bitacora=%s',b),ARRAY['P0001']);
 PERFORM pg_temp.aa_error('owner_truncate_bloqueado','TRUNCATE auditoria.aud_bitacora',ARRAY['P0001']);
 PERFORM pg_temp.aa_as_role('limite_owner_puede_insertar',rol_owner,
  format('INSERT INTO auditoria.aud_bitacora(id_configuracion,id_usuario,id_estacion,id_registro) VALUES(%s,%s,%s,''owner'') RETURNING 1',c,u,e),ARRAY['00000'],'1');
 ok:=false;
 BEGIN
  ALTER TABLE auditoria.aud_bitacora DISABLE TRIGGER USER;
  UPDATE auditoria.aud_bitacora SET valor_nuevo='administracion' WHERE id_bitacora=b;
  SELECT valor_nuevo='administracion' INTO ok FROM auditoria.aud_bitacora WHERE id_bitacora=b;
  RAISE EXCEPTION USING ERRCODE='AA010',MESSAGE='Revertir demostración de límite administrativo';
 EXCEPTION WHEN SQLSTATE 'AA010' THEN NULL;
 END;
 PERFORM pg_temp.aa_check('limite_owner_desactiva_triggers',ok,'Límite demostrado; DDL y UPDATE revertidos en subtransacción');
 PERFORM pg_temp.aa_check('bitacora_fixture_intacta',(SELECT count(*)=1 AND bool_and(valor_nuevo='1') FROM auditoria.aud_bitacora WHERE id_registro='7001'));
END $$;
SELECT * FROM pg_temp.aa_report();
ROLLBACK;
