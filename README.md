# AutoAudit

Sistema de auditoría configurable para PostgreSQL. Permite seleccionar tablas, columnas y eventos (`INSERT`, `UPDATE` y `DELETE`) y generar triggers que guardan el historial con usuario, origen, fecha, registro afectado y valores anteriores y nuevos.

## Estado del proyecto

Actualizado el **10 de noviembre de 2026**.

La rama `main` contiene la estructura de la base de datos, el generador de triggers, las consultas SQL, los controles de seguridad y la interfaz PHP con Sneat para iniciar sesión y configurar la auditoría. El módulo web de historial de esta rama todavía muestra **Módulo en construcción**.

El historial web completo, con filtros, paginación y exportación CSV, las pruebas automatizadas y la guía con capturas reales están subidos en la rama [pruebas-documentacion-interfaz](https://github.com/ocanm-wq/autoaudit/tree/pruebas-documentacion-interfaz). Esa integración sigue separada de `main` para su revisión por el equipo.

## Documentación

- [Documentación técnica del proyecto](docs/AutoAudit_Documentacion_Tecnica.pdf): modelo, diccionario de datos, configuración, instalación y pruebas SQL. La portada incluye campos editables para los cuatro integrantes; ya contiene los datos de Pablo.
- [Guía de uso de la interfaz en PDF](https://github.com/ocanm-wq/autoaudit/blob/pruebas-documentacion-interfaz/docs/AutoAudit_Guia_Interfaz_Final.pdf): 12 páginas y 15 capturas reales, sin cursor.
- [Guía editable en Word](https://github.com/ocanm-wq/autoaudit/blob/pruebas-documentacion-interfaz/docs/AutoAudit_Guia_Interfaz_Final.docx).
- [Guía para leer en GitHub](https://github.com/ocanm-wq/autoaudit/blob/pruebas-documentacion-interfaz/docs/GUIA_INTERFAZ.md).
- [Resultados y límites de las pruebas](https://github.com/ocanm-wq/autoaudit/blob/pruebas-documentacion-interfaz/docs/PRUEBAS_Y_RESULTADOS.md).
- [Detalle de la integración publicada](https://github.com/ocanm-wq/autoaudit/blob/pruebas-documentacion-interfaz/docs/PUBLICACION_GITHUB.md).

Los documentos de la rama de revisión describen esa versión integrada; no deben confundirse con funcionalidades ya fusionadas en `main`.

En el PDF técnico original se actualizó únicamente la portada de integrantes. El contenido y las tablas de mediciones del documento anterior se conservan; los resultados verificables de esta contribución se consultan en los informes enlazados de la rama de revisión.

## Requisitos

- PostgreSQL 18.
- Ubuntu 26.04 LTS, como requisito del proyecto.
- PHP 8.1 o posterior con la extensión `pdo_pgsql` habilitada.
- Un cliente SQL, como DBeaver o `psql`.

La validación registrada en octubre utilizó PostgreSQL 18.6 en el userland Ubuntu 26.04.1 de Docker sobre WSL2 y PHP 8.2.12 en Windows. No equivale a haber validado el arranque de una máquina virtual Ubuntu independiente.

## Instalación de la base de datos

Crear una base nueva para el proyecto. Para probar las cuentas de demostración, usar un clúster de laboratorio: los roles PostgreSQL pertenecen a todo el clúster.

Desde la raíz del repositorio, con las herramientas de PostgreSQL disponibles:

```bash
createdb -U postgres autoaudit
psql -X -U postgres -d autoaudit -v ON_ERROR_STOP=1 -f sql/01_estructura_autoaudit.sql
psql -X -U postgres -d autoaudit -v ON_ERROR_STOP=1 -f sql/03_generador_triggers.sql
psql -X -U postgres -d autoaudit -v ON_ERROR_STOP=1 -f sql/05_consultas_historial.sql
psql -X -U postgres -d autoaudit -v ON_ERROR_STOP=1 -f sql/06_seguridad.sql
```

En DBeaver se pueden abrir esos mismos archivos y ejecutarlos como scripts, en el mismo orden y conectados a la base creada.

Para reproducir la demostración de la interfaz:

1. En `sql/08_datos_demostracion.sql`, ejecutar únicamente las partes A y B, hasta el marcador `FIN PARTE B`. La parte C contiene demostraciones con errores esperados y una llamada de rendimiento; no ejecutar todo el archivo como instalación automática.
2. Ejecutar `sql/09_interfaz.sql` después de 08. Su parte A instala las funciones de diccionario que necesita la interfaz; su parte B habilita las cuentas demo para iniciar sesión.
3. En esta versión de `main`, 09 concede conexión a la base llamada `autoaudit`. Si se usa otro nombre, adaptar ese `GRANT CONNECT` antes de ejecutarlo. La rama de revisión ya contiene el ajuste para usar la base actual.

Si se usan cuentas propias, ejecutar solo la parte A de 09, crear usuarios con `LOGIN` y concederles `aud_admin` o `aud_consulta`, junto con permiso de conexión a la base correspondiente.

## Inicio de la interfaz

La conexión se configura en `app/config.php` o mediante las variables `AUTOAUDIT_DB_HOST`, `AUTOAUDIT_DB_PORT`, `AUTOAUDIT_DB_NAME` y `AUTOAUDIT_APP_NAME`. El usuario y la contraseña se introducen en el formulario de inicio de sesión.

Ejemplo en PowerShell, con PHP en PATH y `pdo_pgsql` habilitada:

```powershell
$env:AUTOAUDIT_DB_HOST = '127.0.0.1'
$env:AUTOAUDIT_DB_PORT = '5432'
$env:AUTOAUDIT_DB_NAME = 'autoaudit'
php -S 127.0.0.1:8080 -t app
```

Abrir [la interfaz local](http://127.0.0.1:8080/login.php). Mantener el servidor PHP activo mientras se usa la aplicación. Este arranque es para uso local de demostración.

| Cuenta demo | Rol | Acceso previsto |
|---|---|---|
| `demo_maria` | `aud_admin` | Configurar auditoría y consultar el historial |
| `demo_luis` | `aud_consulta` | Consultar el historial |
| `demo_ana` | Sin rol de auditoría | Acceso rechazado |

Las contraseñas de demostración están en `sql/09_interfaz.sql` y son exclusivamente para el laboratorio. El historial web terminado se utiliza desde la rama de revisión; en `main` aún está pendiente integrar ese módulo.

## Configuración y consultas

En **Configuración**, la cuenta administradora puede elegir una tabla, marcar columnas y eventos y guardar para generar el trigger. Al cambiar la configuración hay que regenerarlo. La configuración con historial se desactiva en lugar de borrarse.

Las consultas SQL ya están disponibles en `main`:

```sql
SELECT * FROM auditoria.historial_por_usuario('demo_maria');
SELECT * FROM auditoria.historial_por_columna('public', 'cliente', 'correo');
SELECT * FROM auditoria.historial_por_registro('public', 'cliente', '1');
```

Los resultados se pueden exportar desde el cliente SQL. La pantalla web de la rama de revisión permite combinar filtros y descargar todas las filas filtradas en CSV.

## Estructura

| Ruta | Contenido |
|---|---|
| `app/` | Interfaz PHP y recursos locales de Sneat |
| `docs/AutoAudit_Documentacion_Tecnica.pdf` | Documentación técnica y portada de integrantes |
| `sql/01_estructura_autoaudit.sql` | Esquema, siete tablas de auditoría, índices y tabla cliente |
| `sql/02_consultas_diccionario.sql` | Consultas de metadatos; usa parámetros del cliente SQL |
| `sql/03_generador_triggers.sql` | Generación y eliminación de triggers |
| `sql/04_prueba_generador.sql` | Pruebas manuales opcionales |
| `sql/05_consultas_historial.sql` | Vista y funciones de consulta del historial |
| `sql/06_seguridad.sql` | Roles, permisos y protección de la bitácora |
| `sql/07_pruebas_rendimiento.sql` | Función de medición y llamadas de ejemplo |
| `sql/08_datos_demostracion.sql` | Roles ficticios, semilla y demostraciones |
| `sql/09_interfaz.sql` | Diccionario para la interfaz y acceso de cuentas demo |

Los directorios `tests/`, `scripts/`, las capturas y las guías adicionales se encuentran en la rama de revisión.

## Pruebas y rendimiento

La evidencia fechada del 26 de octubre de 2026 se conserva en la rama de revisión. La integración sobre el último aporte de la interfaz aprobó **148 comprobaciones SQL/HTTP**, sin fallos ni bloqueos, y el análisis de sintaxis de nueve archivos PHP. Las ejecuciones previas documentan el backend con benchmark (240 comprobaciones), SQL09, HTTP y navegación; son conjuntos separados y no se suman como un porcentaje de cobertura.

El benchmark registrado utilizó tres repeticiones para 100, 1.000 y 10.000 filas. No se ejecutó 100.000. Las muestras y su variabilidad están en los resultados; no se extrapolan como rendimiento de producción. Esta actualización del README y de la portada no constituye una nueva ejecución de esas pruebas.

**En `main`, no ejecutar `07_pruebas_rendimiento.sql` completo para instalar el sistema:** sus llamadas finales incluyen 100.000 filas. La función de medición es opcional; para instalarla, seleccionar solo su definición y la revocación de permisos. En la rama de revisión esas invocaciones de ejemplo ya están comentadas y las pruebas se ejecutan explícitamente con su runner.

## Seguridad y privacidad

Los roles separan configuración y consulta. Los permisos y triggers restringen la escritura directa sobre la bitácora; propietarios y superusuarios conservan capacidades administrativas. Los roles autorizados pueden ver valores anteriores/nuevos y datos de origen, por lo que corresponde limitar su acceso.

La IP puede ser `NULL` en conexiones por socket. `application_name` describe la aplicación cliente y no prueba por sí solo la identidad de una persona. Retención, anonimización y políticas de consulta deben definirse para cualquier uso fuera del laboratorio. Para desplegar la interfaz fuera del equipo local se requieren HTTPS y almacenamiento de sesiones protegido.

## Integrantes

| Nombre confirmado | Carné |
|---|---|
| Pablo Andres Sanchez Pesquera | 0900-20-17740 |
| David Efraín Valladares Vásquez | 090-20-25247 |

