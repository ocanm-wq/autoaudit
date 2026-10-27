# Comparación del ZIP original y la interfaz (26-10-2026)

**Inspección histórica del ZIP antes de la integración.** Los pendientes descritos aquí fueron resueltos; consultar docs/PUBLICACION_GITHUB.md y la guía actual.

## Alcance

Se compararon los SQL `01` a `08` del proyecto original extraído y la copia local de AutoAudit. La comparación normalizó BOM y finales de línea (`CRLF`/`LF`) antes de calcular SHA-256. No se ejecutó SQL contra ninguna base existente y no se hicieron commits ni cambios en Git.

## Resultado de SQL 01–08

| Archivo | Resultado semántico |
|---|---|
| `01_estructura_autoaudit.sql` | Igual |
| `02_consultas_diccionario.sql` | Igual |
| `03_generador_triggers.sql` | Igual; el generador presente en el ZIP coincide con el original probado |
| `04_prueba_generador.sql` | Igual |
| `05_consultas_historial.sql` | Difiere únicamente en la línea aislada `q`: el ZIP todavía contiene esa línea y la copia local ya la eliminó |
| `06_seguridad.sql` | La copia local incluye correcciones de seguridad posteriores: `SECURITY DEFINER`/`search_path`, privilegios por defecto y manejo explícito de funciones del generador ausentes |
| `07_pruebas_rendimiento.sql` | La copia local dejó las ejecuciones automáticas de 1,000/10,000/100,000 y la aserción de cinco filas como ejemplos comentados; el cuerpo de medición no fue cambiado |
| `08_datos_demostracion.sql` | Igual |

Por tanto, `03` y `08` sí son semánticamente iguales al original previamente probado. La afirmación de que el ZIP solo corrigió `05` es correcta para el proyecto base, pero la copia local también conserva mejoras deliberadas en `06` y `07` realizadas durante la revisión.

## Interfaz

El ZIP de interfaz contiene PHP Sneat, login, panel, configuración y `consulta.php`. `app/consulta.php` declara explícitamente «Módulo en construcción» (líneas 3–10), por lo que el módulo de consultas todavía no está implementado; el resto del flujo no debe documentarse como consulta funcional hasta conectarlo a las funciones de `05`.

Hallazgos concretos:

1. `sql/09_interfaz.sql:181` usa `GRANT CONNECT ON DATABASE autoaudit ...` hardcodeado. En una base de pruebas con otro nombre el script falla o deja los roles sin conexión. Recomendación mínima: ejecutar el GRANT desde la base objetivo o parametrizar el nombre al instalar; no reemplazarlo con una cadena insegura.
2. `sql/09_interfaz.sql:143` concede las funciones de diccionario a `aud_consulta` y asume que `aud_admin` lo hereda. Eso depende de que `aud_admin IN ROLE aud_consulta` siga existiendo; conviene verificarlo en la instalación y documentarlo.
3. `app/lib/auth.php:78` conserva la contraseña PostgreSQL en la sesión del servidor para abrir una conexión en cada petición. Es funcional para la demo, pero requiere almacenamiento de sesiones protegido y HTTPS en cualquier entorno real. `session_set_cookie_params` (líneas 24–29) no marca `secure`; en HTTP local esto es esperable, en HTTPS debe activarse.
4. `app/lib/db.php:44` fija `application_name` mediante `set_config`, lo cual es útil para trazabilidad pero no debe tratarse como identidad de usuario: la identidad real sigue siendo `session_user`.

No se detectó en la revisión estática una inyección SQL evidente en `configuracion.php`: usa consultas preparadas y el generador valida la configuración en PostgreSQL. El bloqueo de `demo_ana` y el alcance de `demo_luis` dependen de ejecutar `09` después de crear los roles de `08`.

## Orden mínimo para integrar

1. Instalar `01`–`08` y luego `09` en una base aislada cuyo nombre se ajuste al `GRANT CONNECT`.
2. Confirmar login de `demo_maria`, `demo_luis` y rechazo de `demo_ana`.
3. Completar `consulta.php` usando las funciones de `05`; no duplicar la lógica SQL.
4. Reejecutar las pruebas funcionales/seguridad y tomar capturas reales del login, configuración y consulta ya operativa.
