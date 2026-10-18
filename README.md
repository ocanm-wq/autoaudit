# AutoAudit

Sistema de auditoría automatizado para bases de datos PostgreSQL. Permite elegir qué tablas y columnas auditar y qué eventos registrar (INSERT, UPDATE, DELETE); el sistema genera automáticamente los triggers que guardan cada cambio en una bitácora centralizada.

## Características

- Configuración de auditoría por tabla, columna y evento.
- Consulta del diccionario de datos para elegir tablas y columnas.
- Generación dinámica de triggers `AFTER` (uno por tabla) en PL/pgSQL.
- Bitácora con valor anterior y nuevo, usuario, estación (IP y aplicación), fecha y hora.
- Consultas de historial por usuario, por columna y por registro.
- Seguridad: roles separados y bitácora de solo escritura.
- Pruebas funcionales y de rendimiento.

## Requisitos

- PostgreSQL 18
- Ubuntu 26.04 LTS (requisito del proyecto)
- Un cliente SQL: DBeaver o `psql`

Entorno donde se probó: _(completar: sistema operativo y versión de PostgreSQL)_

## Estructura del repositorio

| Archivo | Contenido |
|---|---|
| `sql/01_estructura_autoaudit.sql` | Esquema `auditoria`, 7 tablas del sistema, índices y tabla de prueba `public.cliente` |
| `sql/02_consultas_diccionario.sql` | Consultas al diccionario de datos (tablas, columnas, llaves primarias, validaciones) |
| `sql/03_generador_triggers.sql` | Funciones que generan y eliminan los triggers según la configuración |
| `sql/04_prueba_generador.sql` | Ejemplo de uso y prueba de INSERT, UPDATE y DELETE |
| `sql/05_consultas_historial.sql` | Vista y funciones de consulta histórica |
| `sql/06_seguridad.sql` | Roles, permisos y protección de la bitácora |
| `sql/07_pruebas_rendimiento.sql` | Medición de rendimiento con y sin auditoría |

## Instalación

1. Crear la base de datos:

   ```sql
   CREATE DATABASE autoaudit;
   ```

2. Conectarse a `autoaudit`. Si la base no tiene el esquema `public`, crearlo:

   ```sql
   CREATE SCHEMA IF NOT EXISTS public;
   ```

3. Ejecutar los scripts **en orden**, del `01` al `07`, siempre conectado a `autoaudit`.
   - En DBeaver: abrir el archivo en un editor SQL de `autoaudit` y ejecutarlo con **Alt+X**.
   - En `psql`:

     ```bash
     psql -U postgres -d autoaudit -f sql/01_estructura_autoaudit.sql
     ```

Notas:

- `02` usa parámetros de DBeaver (`:esquema`, `:tabla`); en `psql` hay que reemplazarlos por valores.
- `04` y `07` incluyen pruebas; ejecutar `04` por bloques, en orden.
- `07` deja la función creada; las pruebas se ejecutan después, una por una.

## Uso

Ejemplo con la tabla `public.cliente`: auditar `nombre` y `correo` en INSERT, UPDATE y DELETE.

```sql
-- 1. Registrar la tabla y sus columnas
INSERT INTO auditoria.aud_tabla (esquema, nombre_tabla) VALUES ('public', 'cliente');

INSERT INTO auditoria.aud_columna (id_tabla, nombre_columna)
SELECT t.id_tabla, c.nombre
FROM auditoria.aud_tabla t
CROSS JOIN (VALUES ('nombre'), ('correo')) AS c(nombre)
WHERE t.esquema = 'public' AND t.nombre_tabla = 'cliente';

-- 2. Configurar los eventos a auditar
INSERT INTO auditoria.aud_configuracion (id_columna, id_evento)
SELECT col.id_columna, e.id_evento
FROM auditoria.aud_columna col
JOIN auditoria.aud_tabla t ON t.id_tabla = col.id_tabla
CROSS JOIN auditoria.aud_evento e
WHERE t.esquema = 'public' AND t.nombre_tabla = 'cliente';

-- 3. Generar el trigger
SELECT auditoria.generar_trigger(id_tabla)
FROM auditoria.aud_tabla
WHERE esquema = 'public' AND nombre_tabla = 'cliente';
```

Si cambia la configuración, se vuelve a ejecutar `generar_trigger`. Para quitar la auditoría de una tabla: `SELECT auditoria.eliminar_trigger(<id_tabla>);`.

### Consultar el historial

```sql
SELECT * FROM auditoria.historial_por_usuario('postgres');
SELECT * FROM auditoria.historial_por_columna('public', 'cliente', 'correo');
SELECT * FROM auditoria.historial_por_registro('public', 'cliente', '1');
```

Los resultados se pueden exportar desde DBeaver (clic derecho en los resultados, **Export data**, CSV, Excel o JSON).

## Seguridad

- `aud_admin`: configura la auditoría y consulta el historial.
- `aud_consulta`: solo consulta el historial.
- Ningún rol tiene permiso de escritura directa en la bitácora; solo la escriben los triggers.
- Triggers que bloquean `UPDATE`, `DELETE` y `TRUNCATE` sobre la bitácora.
- La IP de origen solo es visible mediante la vista y las funciones de historial.

## Pruebas de rendimiento

Tiempos medidos en el equipo de desarrollo, con la función `auditoria.medir_rendimiento(N)` (columnas `nombre` y `correo` auditadas):

| Filas | Operación | Sin auditoría (ms) | Con auditoría (ms) |
|---|---|---|---|
| 1.000 | INSERT | 7,4 | 271,6 |
| 1.000 | UPDATE | 5,5 | 228,3 |
| 1.000 | DELETE | 0,6 | 277,7 |
| 10.000 | INSERT | 72,0 | 2.993,3 |
| 10.000 | UPDATE | 151,5 | 1.971,5 |
| 10.000 | DELETE | 16,3 | 3.108,2 |
| 100.000 | INSERT | 1.007,7 | 29.827,7 |
| 100.000 | UPDATE | 1.213,4 | 20.156,7 |
| 100.000 | DELETE | 79,1 | 30.407,9 |

Conclusiones:

- El costo crece de forma lineal con el volumen: unos 0,2 a 0,3 ms por fila auditada, sin degradarse al crecer la bitácora.
- En operaciones normales (una o pocas filas) el impacto es pequeño.
- En cargas masivas el impacto es alto: un INSERT de 100.000 filas pasa de 1 s a unos 30 s.

## Estado del proyecto

- [x] Modelo entidad-relación y estructura de tablas
- [x] Consultas al diccionario de datos
- [x] Generador dinámico de triggers
- [x] Consultas de historial
- [x] Seguridad
- [x] Pruebas funcionales y de rendimiento
- [ ] Interfaz de configuración y consulta
- [ ] Documentación técnica en PDF