# Índice de resultados

## Integración con el último commit del equipo

`20261026_publicacion/resultados.json`: 28 funcionales, 47 de seguridad, 35 SQL09 y 38 HTTP, todos aprobados. Es la repetición realizada sobre la rama basada en b978a33, sin benchmark. Incluye hashes de los fuentes comprobados y logs. `20261026_publicacion/http/resultados.json` detalla el HTTP.

## Evidencia final anterior a la publicación

- `20261026_backend_controlado/resultados.json`: backend completo, 240 PASS, 0 FAIL, 0 BLOCKED, incluido benchmark con tres repeticiones para 100/1.000/10.000.
- `20261026_interfaz/resultados_sql09.json`: 35/0/0.
- `20261026_http_verificado/resultados.json`: 38/0/0.
- `20261026_interfaz/resultados_navegador.json`: 29/0/0 y 15 capturas reales. `capturas_manifest.json` contiene sus SHA256.
- `20261026_interfaz/verificacion_final.json`: snapshot de la copia local antes de autorizar commit/push. Su HEAD y rama son históricos.
- `20261026_interfaz/informe_comparacion_backend.*`: inspección original del ZIP, antes de completar consultas y corregir la conexión de SQL09. Sus pendientes fueron resueltos posteriormente.

## Históricos y diagnósticos que no se suman a los finales

- `20261026_backend`: 236/4/0, excluido de estadísticas por tiempos negativos de causa no confirmada.
- `20261026_publicacion_diagnostico_hba`: SQL por socket aprobado; HTTP rechazó login porque faltaba configurar el acceso del puente Docker al clúster desechable. Se corrigió la preparación del laboratorio, no las aserciones ni el código de la aplicación.
- `20261026_http_revisado`: intento con una columna incorrecta en la consulta de comprobación del test; se corrigió a tabla, el nombre real de la vista.
- `20261026_interfaz/diagnostico_selector_navegacion.json` y `fallo_visual.png`: intento cuyo selector no contemplaba el icono del nombre accesible; el guion final se ajustó y pasó 29/0/0.
- `20261026_http`, `20261026_http_final` y otros logs de preparación conservan intentos previos y no reemplazan el HTTP verificado.
- Los directorios de 23 y 25 de octubre son evidencia fechada de fases previas. No deben presentarse como ejecuciones nuevas.

El contexto del entorno, la variabilidad y los límites de seguridad están en docs/PRUEBAS_Y_RESULTADOS.md, RENDIMIENTO_METODOLOGIA.md y PUBLICACION_GITHUB.md.
