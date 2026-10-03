-- =====================================================
-- AutoAudit - 04: Prueba del generador de triggers
-- Ejecutar paso por paso en la base autoaudit.
-- Tabla de prueba: public.cliente
-- Se auditan las columnas nombre y correo (telefono NO se audita).
-- =====================================================

-- 1. Registrar la tabla y sus columnas
INSERT INTO auditoria.aud_tabla (esquema, nombre_tabla)
VALUES ('public', 'cliente');

INSERT INTO auditoria.aud_columna (id_tabla, nombre_columna)
SELECT t.id_tabla, c.nombre
FROM auditoria.aud_tabla t
CROSS JOIN (VALUES ('nombre'), ('correo')) AS c(nombre)
WHERE t.esquema = 'public'
  AND t.nombre_tabla = 'cliente';

-- 2. Configurar: auditar INSERT, UPDATE y DELETE en ambas columnas
INSERT INTO auditoria.aud_configuracion (id_columna, id_evento)
SELECT col.id_columna, e.id_evento
FROM auditoria.aud_columna col
JOIN auditoria.aud_tabla t ON t.id_tabla = col.id_tabla
CROSS JOIN auditoria.aud_evento e
WHERE t.esquema = 'public'
  AND t.nombre_tabla = 'cliente';

-- 3. Generar el trigger
SELECT auditoria.generar_trigger(id_tabla)
FROM auditoria.aud_tabla
WHERE esquema = 'public' AND nombre_tabla = 'cliente';

-- 4. Probar las tres operaciones
INSERT INTO public.cliente (nombre, correo, telefono)
VALUES ('Ana', 'ana@mail.com', '5555-1111');

UPDATE public.cliente
SET correo = 'ana.nueva@mail.com'
WHERE nombre = 'Ana';

DELETE FROM public.cliente
WHERE nombre = 'Ana';

-- 5. Ver la bitácora
-- Resultado esperado: 5 filas
--   INSERT: nombre y correo (2)
--   UPDATE: solo correo, porque nombre no cambió (1)
--   DELETE: nombre y correo (2)
SELECT b.id_bitacora,
       ev.nombre         AS evento,
       col.nombre_columna AS columna,
       b.id_registro,
       b.valor_anterior,
       b.valor_nuevo,
       u.nombre_usuario  AS usuario,
       es.ip_origen,
       b.fecha_hora
FROM auditoria.aud_bitacora b
JOIN auditoria.aud_configuracion cf ON cf.id_configuracion = b.id_configuracion
JOIN auditoria.aud_columna col      ON col.id_columna      = cf.id_columna
JOIN auditoria.aud_evento ev        ON ev.id_evento        = cf.id_evento
JOIN auditoria.aud_usuario u        ON u.id_usuario        = b.id_usuario
JOIN auditoria.aud_estacion es      ON es.id_estacion      = b.id_estacion
ORDER BY b.id_bitacora;
