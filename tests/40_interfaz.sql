-- AutoAudit - integración SQL de la interfaz (09_interfaz.sql)
-- Ejecutar en una base aislada autoaudit_test_* como propietario/superusuario.
BEGIN;
SELECT pg_temp.aa_guard();

DO $$
DECLARE
  r text; n bigint; v text; roles text[] := ARRAY['aud_admin','aud_consulta'];
BEGIN
  -- Las tres funciones de diccionario deben existir y ser SECURITY DEFINER.
  FOREACH r IN ARRAY ARRAY['auditoria.listar_tablas()','auditoria.listar_usuarios()'] LOOP
    PERFORM pg_temp.aa_check('existe_'||replace(split_part(r,'.',2),'()',''),to_regprocedure(r) IS NOT NULL,r);
  END LOOP;
  PERFORM pg_temp.aa_check('existe_listar_columnas',to_regprocedure('auditoria.listar_columnas(text,text)') IS NOT NULL);

  FOREACH r IN ARRAY ARRAY['auditoria.listar_tablas()','auditoria.listar_columnas(text,text)','auditoria.listar_usuarios()'] LOOP
    PERFORM pg_temp.aa_check('security_definer_'||replace(replace(split_part(r,'.',2),'()',''),'(', '_'),
      (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(r)),r);
    PERFORM pg_temp.aa_check('search_path_'||replace(replace(split_part(r,'.',2),'()',''),'(', '_'),
      EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r)
        AND p.proconfig @> ARRAY['search_path=auditoria, pg_temp']),r);
  END LOOP;

  -- Inventario y estados conocidos de las tablas de demostración.
  SELECT count(*) INTO n FROM auditoria.listar_tablas() WHERE esquema='public' AND tabla IN ('cliente','producto');
  PERFORM pg_temp.aa_check('tablas_cliente_producto',n=2,'conteo='||n);
  PERFORM pg_temp.aa_check('excluye_auditoria',NOT EXISTS(SELECT 1 FROM auditoria.listar_tablas() WHERE esquema='auditoria'));
  SELECT count(*) INTO n FROM auditoria.listar_columnas('public','cliente');
  PERFORM pg_temp.aa_check('columnas_cliente',n=4,'conteo='||n);
  SELECT count(*) INTO n FROM auditoria.listar_columnas('public','producto');
  PERFORM pg_temp.aa_check('columnas_producto',n=4,'conteo='||n);
  SELECT count(*) INTO n FROM auditoria.listar_tablas() t
    JOIN auditoria.aud_tabla at ON at.id_tabla=t.id_tabla
    JOIN auditoria.aud_columna ac ON ac.id_tabla=at.id_tabla
    JOIN auditoria.aud_configuracion cf ON cf.id_columna=ac.id_columna AND cf.activa;
  -- La fixture aislada preparada para esta ejecución tiene 10 combinaciones
  -- activas (el valor 11 pertenece a otra captura/demo y no se inventa aquí).
  PERFORM pg_temp.aa_check('eventos_activos_cliente_producto',n=10,'conteo='||n);
  PERFORM pg_temp.aa_check('metadato_cliente_pk',
    (SELECT es_pk FROM auditoria.listar_columnas('public','cliente') WHERE columna='id_cliente'));
  PERFORM pg_temp.aa_check('metadato_producto_pk',
    (SELECT es_pk FROM auditoria.listar_columnas('public','producto') WHERE columna='id_producto'));

  -- Entradas quoted/maliciosas se tratan como datos y no ejecutan SQL.
  SELECT count(*) INTO n FROM auditoria.listar_columnas('public','cliente''; DROP TABLE auditoria.aud_usuario; --');
  PERFORM pg_temp.aa_check('entrada_quoted_segura',n=0,'conteo='||n);
  SELECT count(*) INTO n FROM auditoria.listar_columnas('public''; DROP SCHEMA auditoria CASCADE; --','cliente');
  PERFORM pg_temp.aa_check('entrada_schema_segura',n=0,'conteo='||n);
  PERFORM pg_temp.aa_check('aud_usuario_sigue',to_regclass('auditoria.aud_usuario') IS NOT NULL);

  -- ACL: PUBLIC no ejecuta las funciones; los roles de consulta sí.
  PERFORM pg_temp.aa_check('public_sin_execute_diccionario',NOT EXISTS(
    SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE ns.nspname='auditoria' AND p.proname IN ('listar_tablas','listar_columnas','listar_usuarios')
      AND a.grantee=0 AND a.privilege_type='EXECUTE'));
  FOREACH r IN ARRAY roles LOOP
    PERFORM pg_temp.aa_as_role(r||'_listar_tablas',r,'SELECT count(*) FROM auditoria.listar_tablas()',ARRAY['00000'],'2');
    PERFORM pg_temp.aa_as_role(r||'_listar_columnas',r,'SELECT count(*) FROM auditoria.listar_columnas(''public'',''cliente'')',ARRAY['00000'],'4');
    PERFORM pg_temp.aa_as_role(r||'_listar_usuarios',r,'SELECT count(*) FROM auditoria.listar_usuarios()',ARRAY['00000']);
  END LOOP;

  -- Roles demo creados por 08/09: login y conexión a la base actual.
  FOREACH r IN ARRAY ARRAY['demo_maria','demo_luis','demo_ana'] LOOP
    PERFORM pg_temp.aa_check(r||'_login',(SELECT rolcanlogin FROM pg_roles WHERE rolname=r),
      'rol inexistente o sin LOGIN');
    PERFORM pg_temp.aa_check(r||'_connect_actual',has_database_privilege(r,current_database(),'CONNECT'));
  END LOOP;
  PERFORM pg_temp.aa_check('maria_admin',pg_has_role('demo_maria','aud_admin','USAGE'));
  PERFORM pg_temp.aa_check('luis_consulta',pg_has_role('demo_luis','aud_consulta','USAGE'));
  PERFORM pg_temp.aa_check('ana_sin_rol',NOT pg_has_role('demo_ana','aud_admin','USAGE') AND NOT pg_has_role('demo_ana','aud_consulta','USAGE'));
END $$;

SELECT * FROM pg_temp.aa_report();
ROLLBACK;
