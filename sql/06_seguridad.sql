-- AutoAudit - 06: Seguridad

-- 1. Roles
-- aud_admin    : puede configurar la auditoría y consultar el historial
-- aud_consulta : solo puede consultar el historial

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aud_admin') THEN
        CREATE ROLE aud_admin NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aud_consulta') THEN
        CREATE ROLE aud_consulta NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'usuario_prueba') THEN
        CREATE ROLE usuario_prueba NOLOGIN;  -- solo para las pruebas de la sección 6
    END IF;
END
$$;

GRANT aud_consulta TO aud_admin;

-- 2. Quitar todos los permisos por defecto (PUBLIC) del esquema auditoria
REVOKE ALL ON SCHEMA auditoria FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA auditoria FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA auditoria FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA auditoria FROM PUBLIC;

-- 3. Permisos de aud_admin (configuración) y aud_consulta (lectura)
GRANT USAGE ON SCHEMA auditoria TO aud_admin, aud_consulta;

-- Configuración: solo aud_admin
GRANT SELECT, INSERT, UPDATE ON auditoria.aud_tabla,
                                auditoria.aud_columna,
                                auditoria.aud_configuracion TO aud_admin;
GRANT SELECT ON auditoria.aud_evento TO aud_admin;
GRANT USAGE, SELECT ON  auditoria.aud_tabla_id_tabla_seq,
                        auditoria.aud_columna_id_columna_seq,
                        auditoria.aud_configuracion_id_configuracion_seq TO aud_admin;

-- Generar y eliminar triggers: solo aud_admin
-- (se ejecutan con los permisos del dueño, así el admin no necesita
--  ser dueño de las tablas auditadas)
ALTER FUNCTION auditoria.generar_trigger(INT)
    SECURITY DEFINER SET search_path = auditoria, pg_temp;
ALTER FUNCTION auditoria.eliminar_trigger(INT)
    SECURITY DEFINER SET search_path = auditoria, pg_temp;

GRANT EXECUTE ON FUNCTION   auditoria.generar_trigger(INT),
                            auditoria.eliminar_trigger(INT) TO aud_admin;

-- Consulta de historial: aud_consulta (y aud_admin, que la hereda)
-- La vista se ejecuta con los permisos de su dueño, por eso
-- aud_consulta no necesita acceso directo a la bitácora.
GRANT SELECT ON auditoria.v_historial TO aud_consulta;
GRANT EXECUTE ON FUNCTION
    auditoria.historial_por_usuario(TEXT, TIMESTAMPTZ, TIMESTAMPTZ),
    auditoria.historial_por_columna(TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ),
    auditoria.historial_por_registro(TEXT, TEXT, TEXT)
TO aud_consulta;

-- 4. Bitácora de solo escritura: nadie puede modificarla ni borrarla
-- (ni siquiera el dueño, mientras estos triggers estén activos)
CREATE OR REPLACE FUNCTION auditoria.bloquear_modificacion_bitacora()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'La bitácora es de solo escritura: no se permite % sobre aud_bitacora', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS trg_bitacora_inmutable ON auditoria.aud_bitacora;
CREATE TRIGGER trg_bitacora_inmutable
    BEFORE UPDATE OR DELETE ON auditoria.aud_bitacora
    FOR EACH ROW EXECUTE FUNCTION auditoria.bloquear_modificacion_bitacora();

DROP TRIGGER IF EXISTS trg_bitacora_sin_truncate ON auditoria.aud_bitacora;
CREATE TRIGGER trg_bitacora_sin_truncate
    BEFORE TRUNCATE ON auditoria.aud_bitacora
    FOR EACH STATEMENT EXECUTE FUNCTION auditoria.bloquear_modificacion_bitacora();

-- 6. PRUEBAS
-- Prueba 1: un usuario sin permisos NO puede escribir en la bitácora
-- Esperado: ERROR permission denied for schema auditoria
-- SET ROLE usuario_prueba;
-- INSERT INTO auditoria.aud_bitacora (id_configuracion, id_usuario, id_estacion, id_registro)
-- VALUES (1, 1, 1, 'x');
-- RESET ROLE;

-- Prueba 2: aud_consulta NO puede leer la bitácora directamente
--   Esperado: ERROR permission denied for schema/table
-- SET ROLE aud_consulta;
-- SELECT * FROM auditoria.aud_bitacora;
-- RESET ROLE;

-- Prueba 3: aud_consulta SÍ puede consultar el historial
--   Esperado: las filas del historial
-- SET ROLE aud_consulta;
-- SELECT * FROM auditoria.historial_por_columna('public', 'cliente', 'correo');
-- RESET ROLE;

-- Prueba 4: aud_consulta NO puede generar triggers
--   Esperado: ERROR permission denied for function generar_trigger
-- SET ROLE aud_consulta;
-- SELECT auditoria.generar_trigger(1);
-- RESET ROLE;

-- Prueba 5: aud_admin SÍ puede generar triggers
--   Esperado: Trigger trg_aud_1 creado sobre public.cliente (...)
-- SET ROLE aud_admin;
-- SELECT auditoria.generar_trigger(1);
-- RESET ROLE;

-- Prueba 6: nadie puede borrar la bitácora, ni siquiera el dueño
--   Esperado: ERROR La bitácora es de solo escritura: no se permite DELETE...
-- DELETE FROM auditoria.aud_bitacora WHERE id_bitacora = 1;