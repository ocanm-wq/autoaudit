-- AutoAudit - 01: Estructura de tablas del sistema
-- PostgreSQL 18
CREATE SCHEMA IF NOT EXISTS auditoria;
SET search_path TO auditoria;

-- 1. Eventos auditables (catálogo fijo)
CREATE TABLE aud_evento (
    id_evento   SMALLINT    PRIMARY KEY,
    nombre      VARCHAR(10) NOT NULL UNIQUE
                CHECK (nombre IN ('INSERT', 'UPDATE', 'DELETE'))
);

INSERT INTO aud_evento (id_evento, nombre) VALUES
    (1, 'INSERT'), (2, 'UPDATE'), (3, 'DELETE');

-- 2. Tablas auditadas
CREATE TABLE aud_tabla (
    id_tabla        SERIAL       PRIMARY KEY,
    esquema         VARCHAR(63)  NOT NULL DEFAULT 'public',
    nombre_tabla    VARCHAR(63)  NOT NULL,
    activa          BOOLEAN      NOT NULL DEFAULT TRUE,
    fecha_registro  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (esquema, nombre_tabla)
);

-- 3. Columnas auditadas
CREATE TABLE aud_columna (
    id_columna      SERIAL       PRIMARY KEY,
    id_tabla        INT          NOT NULL REFERENCES aud_tabla (id_tabla),
    nombre_columna  VARCHAR(63)  NOT NULL,
    UNIQUE (id_tabla, nombre_columna)
);

-- 4. Configuración: qué evento se audita en qué columna
CREATE TABLE aud_configuracion (
    id_configuracion SERIAL      PRIMARY KEY,
    id_columna       INT         NOT NULL REFERENCES aud_columna (id_columna),
    id_evento        SMALLINT    NOT NULL REFERENCES aud_evento (id_evento),
    activa           BOOLEAN     NOT NULL DEFAULT TRUE,
    UNIQUE (id_columna, id_evento)
);

-- 5. Usuarios auditados
CREATE TABLE aud_usuario (
    id_usuario      SERIAL       PRIMARY KEY,
    nombre_usuario  VARCHAR(63)  NOT NULL UNIQUE
);

-- 6. Estaciones de trabajo auditadas
CREATE TABLE aud_estacion (
    id_estacion     SERIAL       PRIMARY KEY,
    ip_origen       INET,
    nombre_host     VARCHAR(100),
    UNIQUE (ip_origen, nombre_host)
);

-- 7. Bitácora centralizada
-- Nota: no hay FK hacia las tablas origen, así los datos se
-- conservan aunque el registro fuente sea eliminado.
-- Las configuraciones no se borran, solo se desactivan (activa = FALSE).
CREATE TABLE aud_bitacora (
    id_bitacora      BIGSERIAL      PRIMARY KEY,
    id_configuracion INT            NOT NULL REFERENCES aud_configuracion (id_configuracion)
                                    ON DELETE RESTRICT,
    id_usuario       INT            NOT NULL REFERENCES aud_usuario (id_usuario),
    id_estacion      INT            NOT NULL REFERENCES aud_estacion (id_estacion),
    fecha_hora       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    id_registro      TEXT           NOT NULL,  -- llave primaria del registro afectado
    valor_anterior   TEXT,                     -- NULL en INSERT
    valor_nuevo      TEXT                      -- NULL en DELETE
);

-- Índices para consultas históricas
CREATE INDEX idx_bitacora_usuario  ON aud_bitacora (id_usuario, fecha_hora);
CREATE INDEX idx_bitacora_config   ON aud_bitacora (id_configuracion, fecha_hora);
CREATE INDEX idx_bitacora_fecha    ON aud_bitacora (fecha_hora);

-- Tabla de prueba para auditar (esquema public)
CREATE TABLE IF NOT EXISTS public.cliente (
    id_cliente  SERIAL       PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    correo      VARCHAR(100),
    telefono    VARCHAR(20)
);
