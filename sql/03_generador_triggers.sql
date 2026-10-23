-- AutoAudit - 03: Generador dinámico de triggers
-- PostgreSQL 18 (PL/pgSQL)
-- Ejecutar completo con Alt+X en la base autoaudit.
--
-- Funciones:
--   auditoria.obtener_usuario()        -> id del usuario actual (lo crea si no existe)
--   auditoria.obtener_estacion()       -> id de la estación actual (la crea si no existe)
--   auditoria.eliminar_trigger(id)     -> borra el trigger y su función
--   auditoria.generar_trigger(id)      -> crea/reemplaza el trigger según la configuración
--
-- Por cada tabla auditada se genera:
--   función  auditoria.fn_aud_<id_tabla>()
--   trigger  trg_aud_<id_tabla>  (AFTER, FOR EACH ROW, solo esa tabla)

-- -----------------------------------------------------
-- 1. Usuario actual
-- Se usa session_user (el usuario que inició sesión), porque
-- current_user dentro de SECURITY DEFINER sería el dueño de la función.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION auditoria.obtener_usuario()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    SELECT id_usuario INTO v_id
    FROM auditoria.aud_usuario
    WHERE nombre_usuario = session_user::text;

    IF v_id IS NULL THEN
        INSERT INTO auditoria.aud_usuario (nombre_usuario)
        VALUES (session_user::text)
        ON CONFLICT (nombre_usuario) DO NOTHING;

        SELECT id_usuario INTO v_id
        FROM auditoria.aud_usuario
        WHERE nombre_usuario = session_user::text;
    END IF;

    RETURN v_id;
END;
$$;

-- -----------------------------------------------------
-- 2. Estación actual (IP del cliente + nombre de la aplicación)
-- ip_origen es NULL si la conexión es por socket local.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION auditoria.obtener_estacion()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_ip   INET := inet_client_addr();
    v_host TEXT := NULLIF(current_setting('application_name', true), '');
    v_id   INT;
BEGIN
    SELECT id_estacion INTO v_id
    FROM auditoria.aud_estacion
    WHERE ip_origen   IS NOT DISTINCT FROM v_ip
      AND nombre_host IS NOT DISTINCT FROM v_host;

    IF v_id IS NULL THEN
        INSERT INTO auditoria.aud_estacion (ip_origen, nombre_host)
        VALUES (v_ip, v_host)
        RETURNING id_estacion INTO v_id;
    END IF;

    RETURN v_id;
END;
$$;

-- -----------------------------------------------------
-- 3. Eliminar el trigger y la función de una tabla
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION auditoria.eliminar_trigger(p_id_tabla INT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_tabla auditoria.aud_tabla%ROWTYPE;
    v_reg   regclass;
BEGIN
    SELECT * INTO v_tabla FROM auditoria.aud_tabla WHERE id_tabla = p_id_tabla;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La tabla con id % no está registrada en aud_tabla', p_id_tabla;
    END IF;

    v_reg := to_regclass(format('%I.%I', v_tabla.esquema, v_tabla.nombre_tabla));

    IF v_reg IS NOT NULL THEN
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', 'trg_aud_' || p_id_tabla, v_reg);
    END IF;

    EXECUTE format('DROP FUNCTION IF EXISTS auditoria.%I()', 'fn_aud_' || p_id_tabla);

    RETURN format('Trigger trg_aud_%s eliminado', p_id_tabla);
END;
$$;

-- -----------------------------------------------------
-- 4. Generador principal
-- Lee aud_configuracion y crea la función y el trigger de la tabla.
-- Se puede volver a ejecutar cuando cambie la configuración.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION auditoria.generar_trigger(p_id_tabla INT)
RETURNS TEXT
LANGUAGE plpgsql
AS $gen$
DECLARE
    v_tabla      auditoria.aud_tabla%ROWTYPE;
    v_reg        regclass;
    v_faltantes  TEXT;
    v_pk_cols    TEXT[];
    v_pk_new     TEXT;
    v_pk_old     TEXT;
    v_bloque_ins TEXT;
    v_bloque_upd TEXT;
    v_bloque_del TEXT;
    v_eventos    TEXT;
    v_fn         TEXT := 'fn_aud_'  || p_id_tabla;
    v_trg        TEXT := 'trg_aud_' || p_id_tabla;
BEGIN
    -- Validar que la tabla esté registrada
    SELECT * INTO v_tabla FROM auditoria.aud_tabla WHERE id_tabla = p_id_tabla;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La tabla con id % no está registrada en aud_tabla', p_id_tabla;
    END IF;

    -- Validar que la tabla exista en la base de datos
    v_reg := to_regclass(format('%I.%I', v_tabla.esquema, v_tabla.nombre_tabla));
    IF v_reg IS NULL THEN
        RAISE EXCEPTION 'La tabla %.% no existe en la base de datos',
            v_tabla.esquema, v_tabla.nombre_tabla;
    END IF;

    -- Si la auditoría de la tabla está desactivada, se quita el trigger
    IF NOT v_tabla.activa THEN
        RETURN auditoria.eliminar_trigger(p_id_tabla) || ' (tabla desactivada)';
    END IF;

    -- Validar que las columnas registradas existan
    SELECT string_agg(col.nombre_columna, ', ') INTO v_faltantes
    FROM auditoria.aud_columna col
    WHERE col.id_tabla = p_id_tabla
      AND NOT EXISTS (
          SELECT 1
          FROM pg_attribute a
          WHERE a.attrelid = v_reg::oid
            AND a.attname  = col.nombre_columna
            AND a.attnum   > 0
            AND NOT a.attisdropped
      );
    IF v_faltantes IS NOT NULL THEN
        RAISE EXCEPTION 'Columnas inexistentes en %: %', v_reg, v_faltantes;
    END IF;

    -- Llave primaria (identifica el registro afectado en la bitácora)
    SELECT array_agg(a.attname::text ORDER BY a.attnum) INTO v_pk_cols
    FROM pg_index i
    JOIN pg_attribute a
      ON a.attrelid = i.indrelid
     AND a.attnum   = ANY (i.indkey)
    WHERE i.indrelid = v_reg::oid
      AND i.indisprimary;
    IF v_pk_cols IS NULL THEN
        RAISE EXCEPTION 'La tabla % no tiene llave primaria; es necesaria para identificar el registro', v_reg;
    END IF;

    SELECT string_agg(format('NEW.%I::text', t.col_pk), ', '),
           string_agg(format('OLD.%I::text', t.col_pk), ', ')
    INTO v_pk_new, v_pk_old
    FROM unnest(v_pk_cols) AS t(col_pk);

    -- Bloques de código por evento (id_evento: 1 INSERT, 2 UPDATE, 3 DELETE)
    SELECT
        string_agg(
            format('INSERT INTO auditoria.aud_bitacora (id_configuracion, id_usuario, id_estacion, id_registro, valor_anterior, valor_nuevo) VALUES (%s, v_usuario, v_estacion, v_id, NULL, NEW.%I::text);',
                   cf.id_configuracion, col.nombre_columna),
            E'\n        ') FILTER (WHERE cf.id_evento = 1),
        string_agg(
            format('IF OLD.%2$I IS DISTINCT FROM NEW.%2$I THEN INSERT INTO auditoria.aud_bitacora (id_configuracion, id_usuario, id_estacion, id_registro, valor_anterior, valor_nuevo) VALUES (%1$s, v_usuario, v_estacion, v_id, OLD.%2$I::text, NEW.%2$I::text); END IF;',
                   cf.id_configuracion, col.nombre_columna),
            E'\n        ') FILTER (WHERE cf.id_evento = 2),
        string_agg(
            format('INSERT INTO auditoria.aud_bitacora (id_configuracion, id_usuario, id_estacion, id_registro, valor_anterior, valor_nuevo) VALUES (%s, v_usuario, v_estacion, v_id, OLD.%I::text, NULL);',
                   cf.id_configuracion, col.nombre_columna),
            E'\n        ') FILTER (WHERE cf.id_evento = 3)
    INTO v_bloque_ins, v_bloque_upd, v_bloque_del
    FROM auditoria.aud_configuracion cf
    JOIN auditoria.aud_columna col ON col.id_columna = cf.id_columna
    WHERE col.id_tabla = p_id_tabla
      AND cf.activa;

    v_bloque_ins := COALESCE(v_bloque_ins, 'NULL;');
    v_bloque_upd := COALESCE(v_bloque_upd, 'NULL;');
    v_bloque_del := COALESCE(v_bloque_del, 'NULL;');

    -- Eventos con al menos una columna activa
    SELECT string_agg(s.nombre, ' OR ' ORDER BY s.id_evento) INTO v_eventos
    FROM (
        SELECT DISTINCT e.id_evento, e.nombre
        FROM auditoria.aud_configuracion cf
        JOIN auditoria.aud_columna col ON col.id_columna = cf.id_columna
        JOIN auditoria.aud_evento  e   ON e.id_evento    = cf.id_evento
        WHERE col.id_tabla = p_id_tabla
          AND cf.activa
    ) s;

    IF v_eventos IS NULL THEN
        RETURN auditoria.eliminar_trigger(p_id_tabla) || ' (sin configuración activa)';
    END IF;

    -- Crear la función y el trigger
    BEGIN
        EXECUTE format($tpl$
CREATE OR REPLACE FUNCTION auditoria.%1$I()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auditoria, pg_temp
AS $f$
DECLARE
    v_usuario  INT := auditoria.obtener_usuario();
    v_estacion INT := auditoria.obtener_estacion();
    v_id       TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_id := concat_ws('|', %2$s);
        %3$s
    ELSIF TG_OP = 'UPDATE' THEN
        v_id := concat_ws('|', %2$s);
        %4$s
    ELSIF TG_OP = 'DELETE' THEN
        v_id := concat_ws('|', %5$s);
        %6$s
    END IF;
    RETURN NULL;
END;
$f$
$tpl$, v_fn, v_pk_new, v_bloque_ins, v_bloque_upd, v_pk_old, v_bloque_del);

        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', v_trg, v_reg);

        EXECUTE format(
            'CREATE TRIGGER %I AFTER %s ON %s FOR EACH ROW EXECUTE FUNCTION auditoria.%I()',
            v_trg, v_eventos, v_reg, v_fn);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al generar el trigger de %: %', v_reg, SQLERRM;
    END;

    RETURN format('Trigger %s creado sobre %s (eventos: %s)', v_trg, v_reg, v_eventos);
END;
$gen$;
