-- =====================================================
-- AutoAudit - 02: Consultas al diccionario de datos
-- Ejecutar cada consulta por separado (Ctrl+Enter).
-- En DBeaver, los :parametros abren una ventana para escribir el valor.
-- =====================================================

-- 1. Tablas disponibles para auditar (excluye el esquema del sistema)
SELECT table_schema AS esquema,
       table_name   AS tabla
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_schema NOT IN ('pg_catalog', 'information_schema', 'auditoria')
ORDER BY table_schema, table_name;

-- 2. Columnas de una tabla
--    Ejemplo: esquema = public, tabla = cliente
SELECT column_name      AS columna,
       data_type        AS tipo_dato,
       is_nullable      AS acepta_nulos,
       ordinal_position AS posicion
FROM information_schema.columns
WHERE table_schema = :esquema
  AND table_name   = :tabla
ORDER BY ordinal_position;

-- 3. Llave primaria de una tabla (necesaria para id_registro en la bitácora)
SELECT kcu.column_name AS columna_pk
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
 AND tc.table_schema    = kcu.table_schema
WHERE tc.constraint_type = 'PRIMARY KEY'
  AND tc.table_schema    = :esquema
  AND tc.table_name      = :tabla
ORDER BY kcu.ordinal_position;

-- 4. Validar que una tabla existe (devuelve true / false)
SELECT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = :esquema
      AND table_name   = :tabla
      AND table_type   = 'BASE TABLE'
) AS tabla_existe;

-- 5. Validar que una columna existe en una tabla (devuelve true / false)
SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = :esquema
      AND table_name   = :tabla
      AND column_name  = :columna
) AS columna_existe;
