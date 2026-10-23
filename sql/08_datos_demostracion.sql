-- AutoAudit - 08: Datos de demostración
-- PostgreSQL 18

-- >>> INICIO PARTE A 
-- 1. Roles de demostración
--    demo_app   : puede usar las tablas de ejemplo (cliente y producto)
--    demo_ana   : ventas (usuario normal)
--    demo_luis  : soporte (solo puede consultar el historial)
--    demo_maria : administradora (puede configurar la auditoría)
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['demo_app', 'demo_ana', 'demo_luis', 'demo_maria'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END
$$;

GRANT demo_app TO demo_ana, demo_luis, demo_maria;
GRANT aud_consulta TO demo_luis;
GRANT aud_admin    TO demo_maria;

-- 2. Segunda tabla de ejemplo: producto
CREATE TABLE IF NOT EXISTS public.producto (
    id_producto SERIAL        PRIMARY KEY,
    nombre      VARCHAR(100)  NOT NULL,
    precio      NUMERIC(10,2) NOT NULL,
    stock       INT           NOT NULL DEFAULT 0
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.cliente, public.producto TO demo_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO demo_app;

-- 3. Configuración de la auditoría
--    cliente  : nombre y correo -> INSERT, UPDATE y DELETE
--    producto : precio -> INSERT, UPDATE y DELETE
--               stock  -> solo UPDATE
INSERT INTO auditoria.aud_tabla (esquema, nombre_tabla)
VALUES ('public', 'cliente'), ('public', 'producto')
ON CONFLICT (esquema, nombre_tabla) DO NOTHING;

INSERT INTO auditoria.aud_columna (id_tabla, nombre_columna)
SELECT t.id_tabla, c.col
FROM auditoria.aud_tabla t
JOIN (VALUES ('cliente', 'nombre'), ('cliente', 'correo'),
             ('producto', 'precio'), ('producto', 'stock')) AS c(tabla, col)
  ON c.tabla = t.nombre_tabla
WHERE t.esquema = 'public'
ON CONFLICT (id_tabla, nombre_columna) DO NOTHING;

INSERT INTO auditoria.aud_configuracion (id_columna, id_evento)
SELECT col.id_columna, e.id_evento
FROM auditoria.aud_columna col
JOIN auditoria.aud_tabla t ON t.id_tabla = col.id_tabla
CROSS JOIN auditoria.aud_evento e
WHERE t.esquema = 'public'
  AND (   t.nombre_tabla = 'cliente'
       OR (t.nombre_tabla = 'producto' AND col.nombre_columna = 'precio')
       OR (t.nombre_tabla = 'producto' AND col.nombre_columna = 'stock'
           AND e.nombre = 'UPDATE'))
ON CONFLICT (id_columna, id_evento) DO NOTHING;

-- Generar (o regenerar) los triggers de las dos tablas
SELECT auditoria.generar_trigger(id_tabla)
FROM auditoria.aud_tabla
WHERE esquema = 'public' AND nombre_tabla IN ('cliente', 'producto')
ORDER BY id_tabla;

-- <<< FIN PARTE A ---------------------------------------------------


-- >>> INICIO PARTE B ------------------------------------------------
-- Actividad simulada. Cada usuario trabaja desde una estación distinta
-- (se simula con application_name). Genera 21 registros en la bitácora.

-- Ana (ventas) desde Terminal-Ventas
SET SESSION AUTHORIZATION demo_ana;
SET application_name = 'Terminal-Ventas';

INSERT INTO public.cliente (nombre, correo, telefono)
VALUES ('Carlos Mendez', 'carlos@mail.com', '5555-2001');
INSERT INTO public.cliente (nombre, correo, telefono)
VALUES ('Lucia Perez', 'lucia@mail.com', '5555-2002');
INSERT INTO public.cliente (nombre, correo, telefono)
VALUES ('Jorge Ramos', 'jorge@mail.com', '5555-2003');

UPDATE public.cliente SET correo = 'carlos.mendez@mail.com' WHERE nombre = 'Carlos Mendez';
-- El teléfono NO está configurado para auditoría: este cambio no deja registro
UPDATE public.cliente SET telefono = '5555-9999' WHERE nombre = 'Lucia Perez';

-- Luis (soporte) desde Terminal-Soporte
SET SESSION AUTHORIZATION demo_luis;
SET application_name = 'Terminal-Soporte';

INSERT INTO public.producto (nombre, precio, stock) VALUES ('Teclado', 150.00, 25);
INSERT INTO public.producto (nombre, precio, stock) VALUES ('Mouse',    80.00, 40);
INSERT INTO public.producto (nombre, precio, stock) VALUES ('Monitor', 1200.00, 10);

UPDATE public.producto SET precio = 135.00 WHERE nombre = 'Teclado';
UPDATE public.producto SET stock = stock - 5 WHERE nombre = 'Mouse';
UPDATE public.producto SET stock = stock - 2 WHERE nombre = 'Monitor';

-- María (administradora) desde Laptop-Admin
SET SESSION AUTHORIZATION demo_maria;
SET application_name = 'Laptop-Admin';

UPDATE public.producto SET precio = 1100.00 WHERE nombre = 'Monitor';
UPDATE public.cliente  SET nombre = 'Lucia Perez Soto' WHERE nombre = 'Lucia Perez';
DELETE FROM public.cliente  WHERE nombre = 'Jorge Ramos';
DELETE FROM public.producto WHERE nombre = 'Mouse';

-- Ana otra vez
SET SESSION AUTHORIZATION demo_ana;
SET application_name = 'Terminal-Ventas';

INSERT INTO public.cliente (nombre, correo, telefono)
VALUES ('Sofia Castillo', 'sofia@mail.com', '5555-2004');
UPDATE public.cliente SET correo = 'sofia.castillo@mail.com' WHERE nombre = 'Sofia Castillo';

-- Volver al usuario original
RESET SESSION AUTHORIZATION;
RESET application_name;

-- <<< FIN PARTE B ---------------------------------------------------

-- VERIFICACIÓN DE LA PARTE B (ejecutar con Ctrl+Enter)
SELECT usuario, count(*) AS cambios
FROM auditoria.v_historial
WHERE usuario LIKE 'demo\_%'
GROUP BY usuario
ORDER BY usuario;

-- PARTE C: DEMOSTRACIÓN
-- Paso 1. Qué está configurado para auditoría
SELECT t.nombre_tabla AS tabla, col.nombre_columna AS columna,
       e.nombre AS evento, cf.activa
FROM auditoria.aud_configuracion cf
JOIN auditoria.aud_columna col ON col.id_columna = cf.id_columna
JOIN auditoria.aud_tabla t     ON t.id_tabla     = col.id_tabla
JOIN auditoria.aud_evento e    ON e.id_evento    = cf.id_evento
ORDER BY t.nombre_tabla, col.nombre_columna, e.id_evento;

-- Paso 2. Los triggers que se generaron automáticamente
SELECT c.relname AS tabla, t.tgname AS trigger, t.tgenabled AS habilitado
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname IN ('cliente', 'producto') AND NOT t.tgisinternal;

-- Paso 3. Cambios en vivo (ejecutar las 3, una por una)
INSERT INTO public.cliente (nombre, correo, telefono)
VALUES ('Demo Cliente', 'demo@mail.com', '5555-0000');

UPDATE public.cliente SET correo = 'demo.nuevo@mail.com' WHERE nombre = 'Demo Cliente';

DELETE FROM public.cliente WHERE nombre = 'Demo Cliente';

-- Paso 4. Lo que quedó registrado (los últimos 5 cambios)
SELECT id_bitacora, usuario, tabla, columna, evento, valor_anterior, valor_nuevo
FROM auditoria.v_historial
ORDER BY id_bitacora DESC
LIMIT 5;

-- Paso 5. Historial por usuario, por columna y por registro
SELECT * FROM auditoria.historial_por_usuario('demo_maria');
SELECT * FROM auditoria.historial_por_columna('public', 'producto', 'precio');
SELECT * FROM auditoria.historial_por_registro('public', 'producto', '1');

-- Paso 6. Un registro borrado sigue en la bitácora
--   Jorge Ramos ya no existe en cliente (0 filas)...
SELECT * FROM public.cliente WHERE nombre = 'Jorge Ramos';
--   ...pero su valor sigue en la bitácora
SELECT usuario, columna, evento, valor_anterior, valor_nuevo
FROM auditoria.historial_por_columna('public', 'cliente', 'nombre')
WHERE evento = 'DELETE';

-- Paso 7. Seguridad
--   a) Nadie puede borrar la bitácora. Esperado: ERROR
DELETE FROM auditoria.aud_bitacora WHERE id_bitacora = 1;
--   b) Un usuario de solo consulta no puede generar triggers. Esperado: ERROR permission denied
SET ROLE demo_luis;
SELECT auditoria.generar_trigger(1);
RESET ROLE;
--   c) Pero sí puede consultar el historial. Esperado: sus 6 cambios
SET ROLE demo_luis;
SELECT * FROM auditoria.historial_por_usuario('demo_luis');
RESET ROLE;

-- Paso 8. Rendimiento (tarda unos segundos; no deja datos)
SELECT * FROM auditoria.medir_rendimiento(1000);

-- Paso 9 (opcional). La auditoría se reconfigura en vivo
--   a) Desactivar el evento UPDATE de producto.stock y regenerar el trigger
UPDATE auditoria.aud_configuracion
SET activa = FALSE
WHERE id_columna = (SELECT col.id_columna
                    FROM auditoria.aud_columna col
                    JOIN auditoria.aud_tabla t ON t.id_tabla = col.id_tabla
                    WHERE t.nombre_tabla = 'producto' AND col.nombre_columna = 'stock');

SELECT auditoria.generar_trigger(id_tabla)
FROM auditoria.aud_tabla WHERE nombre_tabla = 'producto';

--   b) Este cambio ya NO deja registro (el trigger no genera nada para stock)
UPDATE public.producto SET stock = stock + 1 WHERE nombre = 'Teclado';

--   c) Volver a activar y regenerar
UPDATE auditoria.aud_configuracion
SET activa = TRUE
WHERE id_columna = (SELECT col.id_columna
                    FROM auditoria.aud_columna col
                    JOIN auditoria.aud_tabla t ON t.id_tabla = col.id_tabla
                    WHERE t.nombre_tabla = 'producto' AND col.nombre_columna = 'stock');

SELECT auditoria.generar_trigger(id_tabla)
FROM auditoria.aud_tabla WHERE nombre_tabla = 'producto';
