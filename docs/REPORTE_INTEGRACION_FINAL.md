# AutoAudit Entrega integrada final

Fecha de cierre local: 26 de octubre de 2026.

**Registro anterior a la autorización para publicar.** Las frases relativas a mantener todos los cambios locales describen esa entrega inicial. El usuario autorizó posteriormente su subida en una rama de revisión; el estado de integración está en PUBLICACION_GITHUB.md.

Se integró la interfaz PHP y Sneat recibida en ZIP y se completó su archivo de consulta, que contenía el mensaje Módulo en construcción. La guía principal tiene 12 páginas y 15 capturas reales de la aplicación, sin puntero. El trabajo permanece local en main, sin staging, commits, push ni publicaciones.

## Archivos y cambios

- `app/`: interfaz del compañero y sus recursos locales Sneat. `consulta.php` incorpora historial por usuario, tabla, columna, evento, registro y fechas; paginación 25/50/100 y CSV de todos los resultados filtrados. Se usan parámetros preparados, validación de entradas, escape HTML, NULL explícito y neutralización de fórmulas en CSV.
- `app/configuracion.php`: ajuste mínimo del enlace Ver historial para conservar la tabla mediante el formato de filtro admitido.
- `app/config.php` y `app/lib/db.php`: zona horaria de conexión America/Guatemala. `login.php` y `lib/auth.php`: rechazo controlado de entradas múltiples.
- `sql/09_interfaz.sql`: funciones de diccionario y cuentas de demostración recibidas; GRANT CONNECT usa la base actual en lugar de un nombre fijo. Su parte A es necesaria para la interfaz; B es exclusiva de demostración.
- Se conservan las correcciones mínimas anteriores de 05, seguridad de 06 y ejemplos pesados comentados de 07. El generador 03 es el del proyecto y no fue reemplazado por una implementación alternativa.
- `tests/`: suites funcionales, de seguridad, rendimiento, SQL09 e integración HTTP; resultados, logs y SHA256. `scripts/iniciar_interfaz.ps1` inicia PHP solo en loopback sin modificar la base ni la configuración global.
- `docs/GUIA_INTERFAZ.md`, `AutoAudit_Guia_Interfaz_Final.docx` y PDF: manual vigente con instalación, roles, configuración, filtros, fechas, CSV y solución de errores. `docs/capturas_interfaz/`: las 15 capturas originales. Los documentos de la fase SQL previa se identifican como históricos.

## Resultados observados

| Ejecución final | PASS | FAIL | BLOCKED |
|---|---:|---:|---:|
| Backend controlado | 240 | 0 | 0 |
| SQL de interfaz | 35 | 0 | 0 |
| Integración HTTP | 38 | 0 | 0 |
| Navegador Chrome | 29 | 0 | 0 |

Son suites separadas. Las rutas exactas y cada caso constan en docs/PRUEBAS_Y_RESULTADOS.md y tests/resultados/20261026_interfaz/verificacion_final.json. Se comprobó que María guarda y regenera triggers, Luis consulta y recibe 403 en configuración, Ana no entra, y cerrar sesión bloquea las consultas posteriores. El enlace de configuración abre 13 eventos de cliente; los filtros combinados producen el cambio de precio 150 a 135. El CSV completo y la paginación se probaron con 68 eventos de un fixture temporal, después eliminado.

El benchmark conserva las tres repeticiones de 100, 1.000 y 10.000 filas con promedios y variabilidad. No se ejecutó 100.000. Una corrida previa 236/4 se conserva excluida por duraciones negativas; su causa no fue confirmada. La repetición controlada pasó completa, aunque el CV de UPDATE de 10.000 filas fue 78,1 %, por lo que no se extrapola a producción. Los intentos anteriores de preparación HTTP y selección del navegador se conservan identificados como diagnósticos.

## Procedencia y límites

Los SHA256 de ambos ZIP recibidos y la comparación del backend se conservan en tests/resultados/20261026_interfaz/. El ZIP original corregido todavía incluía una q aislada en 05; la versión de interfaz ya la corregía y se mantuvo la corrección local verificada. Las contraseñas de sql/09 son únicamente las cuentas ficticias proporcionadas para la demostración y no se imprimen en reportes ni capturas.

Se validó PostgreSQL 18.6 en el userland Ubuntu 26.04.1 de Docker sobre WSL2 y PHP 8.2.12 en Windows. No fue necesario descargar Ubuntu ni arrancar una VM VirtualBox; no se afirma validación de un kernel Ubuntu independiente. El benchmark estuvo sin red; la interfaz utilizó un contenedor distinto con puerto local. No se ejecutaron pruebas sobre el contenedor habitual autoaudit-db ni se enviaron cambios al repositorio remoto.

Los permisos de propietario y superusuario, la retención y anonimización de IP, la identidad detrás de NAT o application_name y la concurrencia se describen con sus límites en la documentación. No se presentan como controles de producción certificados. La guía y el módulo ya no dependen de que otro compañero entregue el código; la aceptación del equipo y la publicación manual quedan a cargo del usuario.

## Uso y repetición

Leer primero docs/GUIA_INTERFAZ.md. En un clúster desechable, instalar 01, 03, 05, 06 y la definición de 07; para la demostración cargar solo 08 A/B y después 09. Iniciar con scripts/iniciar_interfaz.ps1 e ingresar en http://127.0.0.1:8080/login.php. Los comandos de psql, DBeaver y el ejecutor automático están en tests/README.md. No cargar 08 completo como si fuera una suite sin errores esperados.

El cierre y la integridad del paquete se registran junto a esta entrega. No se realizó git add, commit, push, merge, rebase, PR, cambio de identidad ni modificación del historial. HEAD continúa en 561de0e77231ee4215decceab60457182216856b y el índice permanece vacío.
