-- AutoAudit - 09: Apoyo para la interfaz web
-- PostgreSQL 18
--
-- Ejecutar DESPUÉS de 06 (seguridad) y, si se quiere la demostración,
-- después de 08 (datos de demostración).
--
-- Contiene:
--   A. Funciones de diccionario para la interfaz (SECURITY DEFINER)
--   B. Roles de demostración con permiso de inicio de sesión
--
-- Por qué hacen falta las funciones de la parte A:
-- information_schema y pg_class solo muestran los objetos sobre los que el
-- usuario tiene algún privilegio. El rol aud_admin no tiene permisos sobre
-- las tablas de negocio (public.cliente, public.producto), así que por sí
-- solo no podría listarlas para elegir qué auditar. Estas funciones se
-- ejecutan con los permisos de su dueño (SECURITY DEFINER) y solo exponen
-- nombres de tablas y columnas, nunca su contenido.

-- =====================================================================
-- A. Funciones de diccionario para la interfaz
-- =====================================================================

-- A.1 Tablas candidatas a auditoría, con su estado actual
CREATE OR REPLACE FUNCTION auditoria.listar_tablas()
RETURNS TABLE (
    esquema         TEXT,
    tabla           TEXT,
    id_tabla        INT,
    activa          BOOLEAN,
    eventos_activos BIGINT,
    tiene_trigger   BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = auditoria, pg_temp
AS $$
    SELECT  n.nspname::text,
            c.relname::text,
            t.id_tabla,
            COALESCE(t.activa, FALSE),
            (SELECT count(*)
             FROM auditoria.aud_configuracion cf
             JOIN auditoria.aud_columna col ON col.id_columna = cf.id_columna
             WHERE col.id_tabla = t.id_tabla
               AND cf.activa),
            EXISTS (SELECT 1
                    FROM pg_trigger tg
                    WHERE tg.tgrelid = c.oid
                      AND NOT tg.tgisinternal
                      AND tg.tgname = 'trg_aud_' || t.id_tabla)
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN auditoria.aud_tabla t
           ON t.esquema = n.nspname
          AND t.nombre_tabla = c.relname
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'auditoria')
      AND n.nspname NOT LIKE 'pg_%'
    ORDER BY n.nspname, c.relname;
$$;

-- A.2 Columnas de una tabla con su configuración de auditoría
CREATE OR REPLACE FUNCTION auditoria.listar_columnas(
    p_esquema TEXT,
    p_tabla   TEXT
)
RETURNS TABLE (
    columna    TEXT,
    tipo_dato  TEXT,
    es_pk      BOOLEAN,
    aud_insert BOOLEAN,
    aud_update BOOLEAN,
    aud_delete BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = auditoria, pg_temp
AS $$
    WITH reg AS (
        SELECT to_regclass(format('%I.%I', p_esquema, p_tabla)) AS rel
    ),
    cols AS (
        SELECT  a.attname::text                            AS columna,
                format_type(a.atttypid, a.atttypmod)       AS tipo_dato,
                a.attnum,
                EXISTS (SELECT 1
                        FROM pg_index i
                        WHERE i.indrelid = a.attrelid
                          AND i.indisprimary
                          AND a.attnum = ANY (i.indkey))   AS es_pk
        FROM pg_attribute a
        JOIN reg ON a.attrelid = reg.rel
        WHERE a.attnum > 0
          AND NOT a.attisdropped
    ),
    cfg AS (
        SELECT  col.nombre_columna,
                cf.id_evento,
                cf.activa
        FROM auditoria.aud_columna col
        JOIN auditoria.aud_tabla t ON t.id_tabla = col.id_tabla
        LEFT JOIN auditoria.aud_configuracion cf ON cf.id_columna = col.id_columna
        WHERE t.esquema = p_esquema
          AND t.nombre_tabla = p_tabla
    )
    SELECT  c.columna,
            c.tipo_dato,
            c.es_pk,
            COALESCE(bool_or(cfg.id_evento = 1 AND cfg.activa), FALSE),
            COALESCE(bool_or(cfg.id_evento = 2 AND cfg.activa), FALSE),
            COALESCE(bool_or(cfg.id_evento = 3 AND cfg.activa), FALSE)
    FROM cols c
    LEFT JOIN cfg ON cfg.nombre_columna = c.columna
    GROUP BY c.columna, c.tipo_dato, c.es_pk, c.attnum
    ORDER BY c.attnum;
$$;

-- A.3 Usuarios que aparecen en la bitácora (para los filtros de consulta)
CREATE OR REPLACE FUNCTION auditoria.listar_usuarios()
RETURNS TABLE (nombre_usuario TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = auditoria, pg_temp
AS $$
    SELECT u.nombre_usuario::text
    FROM auditoria.aud_usuario u
    ORDER BY u.nombre_usuario;
$$;

-- A.4 Permisos de las funciones de diccionario
-- Solo exponen nombres de tablas y columnas, por eso las puede usar
-- cualquiera de los dos roles del sistema.
REVOKE ALL ON FUNCTION auditoria.listar_tablas()                FROM PUBLIC;
REVOKE ALL ON FUNCTION auditoria.listar_columnas(TEXT, TEXT)    FROM PUBLIC;
REVOKE ALL ON FUNCTION auditoria.listar_usuarios()              FROM PUBLIC;

GRANT EXECUTE ON FUNCTION  auditoria.listar_tablas(),
                           auditoria.listar_columnas(TEXT, TEXT),
                           auditoria.listar_usuarios()
TO aud_consulta;   -- aud_admin lo hereda


-- =====================================================================
-- B. Roles de demostración con inicio de sesión
-- =====================================================================
-- Los roles de 08 se crean como NOLOGIN. La interfaz web pide usuario y
-- contraseña y se conecta a PostgreSQL con ellos, así que para la
-- demostración necesitan LOGIN y una contraseña.
--
-- IMPORTANTE: estas contraseñas son solo para la demostración del curso.
-- Cámbialas antes de usar el sistema en cualquier otro entorno.
--
--   demo_maria -> administradora (configura la auditoría y consulta)
--   demo_luis  -> soporte (solo consulta el historial)
--   demo_ana   -> ventas (sin acceso al sistema de auditoría)

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM (VALUES
                ('demo_maria', 'Maria.2026'),
                ('demo_luis',  'Luis.2026'),
                ('demo_ana',   'Ana.2026')
             ) AS v(rol, clave)
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.rol) THEN
            EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', r.rol, r.clave);
        ELSE
            RAISE NOTICE 'El rol % no existe; ejecute primero 08_datos_demostracion.sql', r.rol;
        END IF;
    END LOOP;
END
$$;

-- La interfaz se conecta a la base de datos autoaudit, así que los tres
-- usuarios necesitan poder conectarse a ella.
GRANT CONNECT ON DATABASE autoaudit TO demo_maria, demo_luis, demo_ana;


-- =====================================================================
-- PRUEBAS (ejecutar una por una)
-- =====================================================================
-- 1. Tablas disponibles con su estado
-- SELECT * FROM auditoria.listar_tablas();

-- 2. Columnas de cliente con su configuración
-- SELECT * FROM auditoria.listar_columnas('public', 'cliente');

-- 3. Un usuario de solo consulta puede listar el diccionario...
-- SET ROLE demo_luis;
-- SELECT * FROM auditoria.listar_tablas();
-- RESET ROLE;

-- 4. ...pero sigue sin poder configurar. Esperado: ERROR permission denied
-- SET ROLE demo_luis;
-- SELECT auditoria.generar_trigger(1);
-- RESET ROLE;
