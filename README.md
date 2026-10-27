# AutoAudit

Sistema de auditoría automatizado para bases de datos PostgreSQL. Permite elegir qué tablas y columnas auditar y qué eventos registrar (INSERT, UPDATE, DELETE); el sistema genera automáticamente los triggers que guardan cada cambio en una bitácora centralizada.

**Estado de esta copia al 26/10/2026:** interfaz PHP Sneat integrada con historial, filtros, paginación y CSV. Las ejecuciones finales aprobaron 240 casos del backend, 35 del SQL de interfaz, 38 por HTTP y 29 del navegador. Guía principal: [Word](docs/AutoAudit_Guia_Interfaz_Final.docx), [PDF](docs/AutoAudit_Guia_Interfaz_Final.pdf) y [Markdown](docs/GUIA_INTERFAZ.md), con 15 capturas reales sin cursor. Evidencia y límites: [PRUEBAS_Y_RESULTADOS.md](docs/PRUEBAS_Y_RESULTADOS.md).

## Integración con los cambios del equipo

La rama `pruebas-documentacion-interfaz` parte del commit `b978a33` que incorporó la interfaz del compañero. Conserva sus recursos Sneat, el generador y la corrección de 05. Añade las consultas pendientes, los ajustes mínimos de seguridad y conexión, las pruebas y las guías.

Sobre esta integración se repitieron 28 casos funcionales, 47 de seguridad, 35 de SQL09 y 38 por HTTP: **148 PASS, 0 FAIL, 0 BLOCKED**, además del lint de los nueve PHP. La corrida anterior del backend con benchmark (240/0/0) se mantiene como evidencia separada y no se presenta como una nueva medición de rendimiento. Detalles en [PUBLICACION_GITHUB.md](docs/PUBLICACION_GITHUB.md).

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
- PHP 8.1 o posterior con `pdo_pgsql` para la interfaz

Entorno y versiones realmente comprobados: [VALIDACION_ENTORNO.md](docs/VALIDACION_ENTORNO.md). Las limitaciones y dependencias pendientes se documentan con los resultados.

Guía de instalación y uso de la interfaz: [GUIA_INTERFAZ.md](docs/GUIA_INTERFAZ.md). Para iniciar en Windows: `.\scripts\iniciar_interfaz.ps1 -DbName autoaudit -DbPort 5432 -Port 8080`. La guía anterior [GUIA_DE_USO.md](docs/GUIA_DE_USO.md) conserva las consultas SQL de la fase previa.

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

3. Para pruebas, usar una base `autoaudit_test` de un clúster dedicado y seguir `tests/README.md`. La estructura se instala con `01`, el generador real con `03`, las consultas con `05`, los controles con `06` y la definición de medición con `07`. `02` son consultas de diccionario; `04` es una prueba manual opcional.
   - En DBeaver: abrir el archivo en un editor SQL de `autoaudit` y ejecutarlo con **Alt+X**.
   - En `psql`:

     ```bash
     psql -U postgres -d autoaudit -f sql/01_estructura_autoaudit.sql
     ```

Notas:

- `02` usa parámetros de DBeaver (`:esquema`, `:tabla`); en `psql` hay que reemplazarlos por valores.
- `04` es una prueba manual dependiente del generador; la ejecución automatizada usa sus propios fixtures y no requiere ejecutarla aparte.
- `07` deja la función creada; sus ejemplos están comentados para impedir cargas automáticas. El wrapper ejecuta 100, 1.000 y 10.000 cuando existe el generador. 100.000 requiere habilitación explícita.
- `06` revoca el EXECUTE público por defecto para funciones futuras del creador actual en todos los esquemas de esta base. Usar un propietario dedicado y revisar ese alcance; no afecta automáticamente a otros creadores.

## Uso

El ejemplo siguiente muestra la configuración de `public.cliente`; la ejecución integrada ya acredita captura automática con el generador real.

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
- `aud_admin` y `aud_consulta` no tienen permiso de escritura directa en la bitácora. El dueño y los superusuarios conservan capacidades administrativas; no es una protección inviolable frente a ellos.
- Triggers que bloquean `UPDATE`, `DELETE` y `TRUNCATE` sobre la bitácora.
- Los dos roles pueden consultar la IP mediante la vista y las funciones de historial. La suite principal usó socket Unix, donde la IP puede ser `NULL`; una demostración TCP separada registró `172.17.0.1` desde Adminer en el clúster de capturas. El dueño, superusuarios y otros roles con permisos directos también pueden acceder.

## Pruebas de rendimiento

La siguiente tabla se conserva del README original. No se verificó su entorno ni procedencia; no constituye una medición nueva ni evidencia del estado actual. Los resultados verificables de esta contribución están en `docs/PRUEBAS_Y_RESULTADOS.md`.

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

Conclusiones heredadas de esa copia, no validadas en esta revisión:

- El costo crece de forma lineal con el volumen: unos 0,2 a 0,3 ms por fila auditada, sin degradarse al crecer la bitácora.
- En operaciones normales (una o pocas filas) el impacto es pequeño.
- En cargas masivas el impacto es alto: un INSERT de 100.000 filas pasa de 1 s a unos 30 s.

## Estado del proyecto

- [x] Modelo entidad-relación y estructura de tablas
- [x] Consultas al diccionario de datos
- [x] Generador dinámico de triggers
- [x] Consultas de historial
- [x] Seguridad
- [x] Suites automatizadas de estructura, consultas y seguridad disponibles
- [x] Ejecución de DML y rendimiento con el generador real (100, 1.000 y 10.000 filas; tres repeticiones)
- [x] Interfaz PHP Sneat de configuración y consulta integrada; evidencia HTTP y navegación en `tests/resultados/20261026_interfaz/`
- [x] Archivo PDF técnico existente; guía de uso y validación actualizada con capturas, y documentos técnicos en `docs/`
