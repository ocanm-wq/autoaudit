-- AutoAudit - 05: Consultas parametrizadas de historial
-- 1. Vista base: la bitácora con nombres legibles
CREATE OR REPLACE VIEW auditoria.v_historial AS
SELECT b.id_bitacora,
        b.fecha_hora,
        u.nombre_usuario   AS usuario,
        es.ip_origen,
        es.nombre_host,
        t.esquema,
        t.nombre_tabla     AS tabla,
        col.nombre_columna AS columna,
        ev.nombre          AS evento,
        b.id_registro,
        b.valor_anterior,
        b.valor_nuevo
FROM auditoria.aud_bitacora b
JOIN auditoria.aud_configuracion cf ON cf.id_configuracion = b.id_configuracion
JOIN auditoria.aud_columna col      ON col.id_columna      = cf.id_columna
JOIN auditoria.aud_tabla t          ON t.id_tabla          = col.id_tabla
JOIN auditoria.aud_evento ev        ON ev.id_evento        = cf.id_evento
JOIN auditoria.aud_usuario u        ON u.id_usuario        = b.id_usuario
JOIN auditoria.aud_estacion es      ON es.id_estacion      = b.id_estacion;

-- 2. Consultas parametrizadas (funciones)
-- 2.1 Cambios realizados por un usuario
CREATE OR REPLACE FUNCTION auditoria.historial_por_usuario(
    p_usuario TEXT,
    p_desde   TIMESTAMPTZ DEFAULT NULL,
    p_hasta   TIMESTAMPTZ DEFAULT NULL
)
RETURNS SETOF auditoria.v_historial
LANGUAGE sql
    STABLE
AS $$
    SELECT *
    FROM auditoria.v_historial h
    WHERE h.usuario = p_usuario
        AND (p_desde IS NULL OR h.fecha_hora >= p_desde)
        AND (p_hasta IS NULL OR h.fecha_hora <  p_hasta)
    ORDER BY h.fecha_hora, h.id_bitacora;
$$;

-- 2.2 Cambios en una columna específica
CREATE OR REPLACE FUNCTION auditoria.historial_por_columna(
    p_esquema TEXT,
    p_tabla   TEXT,
    p_columna TEXT,
    p_desde   TIMESTAMPTZ DEFAULT NULL,
    p_hasta   TIMESTAMPTZ DEFAULT NULL
)

RETURNS SETOF auditoria.v_historial
LANGUAGE sql
    STABLE
    AS $$
        SELECT *
        FROM auditoria.v_historial h
        WHERE h.esquema = p_esquema
            AND h.tabla   = p_tabla
            AND h.columna = p_columna
            AND (p_desde IS NULL OR h.fecha_hora >= p_desde)
            AND (p_hasta IS NULL OR h.fecha_hora <  p_hasta)
        ORDER BY h.fecha_hora, h.id_bitacora;
    $$;

-- 2.3 Historial completo de un registro (por su llave primaria)
CREATE OR REPLACE FUNCTION auditoria.historial_por_registro(
    p_esquema     TEXT,
    p_tabla       TEXT,
    p_id_registro TEXT
)
RETURNS SETOF auditoria.v_historial
LANGUAGE sql
STABLE
    AS $$
        SELECT *
        FROM auditoria.v_historial h
        WHERE h.esquema     = p_esquema
            AND h.tabla       = p_tabla
            AND h.id_registro = p_id_registro
        ORDER BY h.fecha_hora, h.id_bitacora;
    $$;

-- 3. Ejemplos de uso (ejecutar uno por uno)
-- Ver qué usuarios hay registrados
SELECT nombre_usuario FROM auditoria.aud_usuario;
-- Por usuario (cambia 'postgres' por tu usuario)
SELECT * FROM auditoria.historial_por_usuario('postgres');
-- Por usuario en las últimas 24 horas
SELECT * FROM auditoria.historial_por_usuario('postgres', now() - interval '1 day', now());
-- Por columna
SELECT * FROM auditoria.historial_por_columna('public', 'cliente', 'correo');
-- Historial del registro con id 1
SELECT * FROM auditoria.historial_por_registro('public', 'cliente', '1');