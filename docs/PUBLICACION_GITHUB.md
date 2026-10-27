# Integración para revisión en GitHub

El usuario autorizó expresamente subir los cambios el 26/10/2026, después de comprobar su colaboración con la cuenta `psanchezp2`. La API de GitHub confirmó `push: true`, con `admin: false`. Se emplea la identidad Git ya configurada, sin modificar nombre, correo ni añadir atribuciones automáticas.

## Base y alcance

La rama `pruebas-documentacion-interfaz` parte de `b978a33c1b0083d70839795d8f96c4cdf3074641`, el commit más reciente del compañero al preparar la integración. Se compararon los archivos publicados con los ZIP recibidos. Los PHP y SQL09 recibidos coincidían con esa base antes de aplicar nuestros ajustes. Se mantuvieron el diseño, los assets, el generador 03, la corrección ya publicada de 05 y los datos de demostración 08.

Los cambios de aplicación completan `app/consulta.php` con filtros, fechas, paginación y CSV; adaptan el enlace Ver historial de configuración; establecen la zona horaria de la conexión y controlan parámetros múltiples en login/CSRF. En SQL06 se conservan los ajustes de privilegios por defecto y de las funciones; SQL07 deja las cargas de rendimiento como ejemplos comentados; SQL09 concede conexión sobre la base actual.

Se agregan las pruebas SQL, el test HTTP, sus evidencias, las guías Word/PDF con 15 capturas reales y el lanzador local. La copia de trabajo original sigue en main con sus cambios locales; la preparación se hizo en un checkout separado basado en la última versión remota para conservar el trabajo del equipo. No se sustituye main ni se elimina historial.

## Validación repetida sobre esta integración

| Comprobación | PASS | FAIL | BLOCKED |
|---|---:|---:|---:|
| Funcionales SQL | 28 | 0 | 0 |
| Seguridad SQL | 47 | 0 | 0 |
| SQL09 e interfaz | 35 | 0 | 0 |
| HTTP con fixture temporal | 38 | 0 | 0 |
| Total de estas suites | 148 | 0 | 0 |

Los nueve archivos PHP pasaron `php -l`. La evidencia está en `tests/resultados/20261026_publicacion/resultados.json` y sus logs. El test HTTP comprobó las tres cuentas demo, restricciones 403, enlace Ver historial, filtros, entradas inválidas, paginación 25/50/100, CSV completo, escape HTML y limpieza del fixture. La semilla volvió a 21 eventos después de las pruebas. Se utilizó un contenedor exclusivo con PostgreSQL 18.6, límite de 2 CPU, 1 GiB y tmpfs de 768 MiB, más PHP 8.2.12. Solo se publicó el puerto de PostgreSQL en 127.0.0.1. El contenedor y sus sesiones temporales se retiraron al terminar.

El primer intento de este laboratorio no admitió la conexión de PHP desde el puente de Docker: los SQL por socket pasaron, pero el HTTP no pudo iniciar sesión. Se conserva en `20261026_publicacion_diagnostico_hba`. Se configuró autenticación SCRAM para ese acceso del laboratorio y la repetición HTTP aprobó 38 casos. No se modificó el código de la aplicación para hacer pasar esa repetición.

La medición anterior del backend 240/0/0 y el navegador 29/0/0 son ejecuciones previas, documentadas con sus fuentes y capturas. No se volvió a ejecutar el benchmark de 100/1.000/10.000 durante esta integración y no se ejecutó 100.000. La corrida histórica con tiempos negativos continúa excluida del análisis.

## Lectura de la evidencia histórica

Los informes de inspección inicial del ZIP describen el archivo consulta.php antes de completarlo y el GRANT CONNECT antes de corregirlo. No representan el estado actual de esta rama. La verificación local con HEAD 561de0e y la frase sin commit corresponden al cierre anterior a esta autorización. Cada conjunto de resultados se identifica en `tests/resultados/README.md`.

Los únicos usuarios y contraseñas de ejemplo son los que el equipo ya publicó en SQL09 para la demostración. No se incorporan tokens, claves privadas, credenciales reales de PostgreSQL ni archivos de sesión. La contraseña usada al entrar se conserva en la sesión del servidor por el diseño existente; el uso fuera del laboratorio requiere HTTPS y almacenamiento de sesiones protegido, como se describe en SEGURIDAD_Y_PRIVACIDAD.md.

Los cambios quedan preparados en una rama de revisión; no se ha solicitado fusionarlos automáticamente con main ni crear un pull request.
