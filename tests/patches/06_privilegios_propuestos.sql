-- PROPUESTA para integrar manualmente en 06, después de revisar con el equipo.
-- No la carga run_tests.py. Sin COMMIT: demostrar y revertir en entorno aislado.
-- Cargar 00_comun.sql antes, en una conexión nueva.
BEGIN;
DO $$ BEGIN
  IF current_database() !~ '^autoaudit_test(_[a-z0-9]+)?$' THEN
    RAISE EXCEPTION 'Propuesta permitida solo en base de pruebas';
  END IF;
END $$;
-- Añadir inmediatamente después de CREATE FUNCTION bloquear_modificacion_bitacora.
REVOKE ALL ON FUNCTION auditoria.bloquear_modificacion_bitacora() FROM PUBLIC;
-- Añadir ANTES de crear futuras funciones, para CADA propietario creador real.
-- Aquí se aplica únicamente al rol actual; no cubre automáticamente otros roles.
-- Sin IN SCHEMA: un REVOKE por esquema no elimina el permiso global por defecto.
-- Abarca futuras funciones de este creador en TODOS los esquemas de esta base.
-- Antes de integrarlo, usar un propietario dedicado o revisar ese alcance con el equipo.
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- Inspección verificable de la propuesta.
SELECT pg_temp.aa_check('propuesta_funciones_actuales',NOT EXISTS (
 SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 WHERE n.nspname='auditoria' AND a.grantee=0 AND a.privilege_type='EXECUTE'
));
CREATE FUNCTION auditoria.aa_propuesta_futura() RETURNS integer LANGUAGE sql AS 'SELECT 1';
SELECT pg_temp.aa_check('propuesta_funciones_futuras',NOT EXISTS (
 SELECT FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 WHERE p.oid='auditoria.aa_propuesta_futura()'::regprocedure AND a.grantee=0 AND a.privilege_type='EXECUTE'
));
SELECT * FROM pg_temp.aa_report();
DO $$ BEGIN
 IF EXISTS(SELECT FROM pg_temp.aa_results WHERE estado<>'PASS') THEN
  RAISE EXCEPTION 'La propuesta no superó las verificaciones';
 END IF;
END $$;
ROLLBACK;
