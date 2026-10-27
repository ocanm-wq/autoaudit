# Seguridad y privacidad

Este documento distingue el análisis del código SQL de los controles que deben probarse en una base aislada. No se presentan resultados de ejecución que no hayan sido observados.

## Controles definidos

`06_seguridad.sql` contiene la creación de los roles `aud_admin`, `aud_consulta` y `usuario_prueba`, las revocaciones de `PUBLIC` y permisos de configuración/consulta. También convierte los generadores reales en `SECURITY DEFINER` con `search_path = auditoria, pg_temp`.

La vista y las funciones exponen el historial completo a `aud_consulta` y, por herencia, a `aud_admin`. No hay filtro de IP ni separación por usuario/tabla en esos permisos. La captura automática se validó con `03`; la suite integrada usó socket Unix, donde la IP puede ser `NULL`. Una demostración separada sí comprobó TCP local, como muestra `docs/capturas/09_origen.jpg`. NAT y proxies pueden compartir una IP; `application_name` lo controla el cliente; `nombre_host` no demuestra identidad de equipo.

Los triggers de inmutabilidad bloquean `UPDATE`, `DELETE` y `TRUNCATE` sobre la bitácora mientras estén instalados. Propietarios y superusuarios conservan capacidades administrativas de PostgreSQL, por lo que pueden desactivar triggers o cambiar privilegios; esa posibilidad debe documentarse y auditarse operativamente.

## Límites y pendientes

El repositorio no implementa una política automática de conservación, anonimización o borrado por antigüedad. La organización debe definir una retención proporcional a su finalidad y obligaciones aplicables antes de activar purgas. Tampoco se debe tratar la IP, el nombre de estación o `application_name` como prueba suficiente de identidad.

La suite `tests/20_seguridad.sql` distingue las verificaciones de controles disponibles de las que requieren el generador real. Debe ejecutarse como dueño/superusuario en un clúster desechable, con base `autoaudit_test` o `autoaudit_test_<sufijo>`. Las suites revierten sus fixtures y cambios de roles. También debe considerarse que `aud_admin` puede editar metadatos de configuración: el historial hace JOIN con nombres actuales, por lo que esas ediciones pueden reinterpretar registros anteriores aunque no cambien la bitácora.

| Área | Qué define el diseño | Estado observado | Recomendación |
| --- | --- | --- | --- |
| Roles y ACL | `aud_admin` configura; `aud_consulta` consulta; `PUBLIC` queda sin USAGE al esquema | Probado con 03/06 integrados | Mantener roles de acceso separados del propietario |
| Bitácora | Triggers bloquean `UPDATE`, `DELETE` y `TRUNCATE` | Probado con fixture existente y errores esperados | Mantener vigilancia de cambios DDL y privilegios |
| Funciones protegidas | Generadores `SECURITY DEFINER`, `search_path` fijo y `EXECUTE` limitado | PASS en ejecución integrada | Revisar propietario, `proconfig`, ACL actual y privilegios por defecto |
| Privacidad | IP, estación y `application_name` pueden formar parte del historial | Socket probado en la suite; TCP local probado aparte en la demostración | Limitar exposición por rol, documentar NAT/socket y validar finalidad y retención |

Las exportaciones de historial pueden contener IP y datos OLD/NEW sensibles. Se recomienda limitar los lectores según finalidad, ofrecer una vista sin IP cuando no sea necesaria, proteger copias/exportaciones y registrar consultas administrativas. Son recomendaciones; no hay todavía una política de acceso por finalidad, anonimización, retención automática ni purga. El equipo debe acordar responsable y plazo de conservación antes de usar información real. Los triggers inmutables no constituyen almacenamiento inviolable frente a administradores.

## Evidencia de ejecución disponible

El registro `tests/resultados/20261025_integrado/resultados.json` documenta la ejecución integrada en Ubuntu 26.04.1 LTS con PostgreSQL 18.6 en contenedor sin red sobre WSL2, tmpfs 768 MiB, 1 GiB de memoria y 2 CPU. El conjunto final tiene 240 PASS, 0 FAIL y 0 BLOCKED. Se observaron denegaciones `42501`, consultas autorizadas, bloqueos `P0001` y operaciones reales de generar/eliminar trigger. La suite principal usó socket Unix; allí la IP puede ser `NULL` y TCP no forma parte de esa ejecución. La captura separada `docs/capturas/09_origen.jpg` sí documenta una conexión TCP local con IP `172.17.0.1` y aplicación Adminer; identifica el origen de la conexión en ese entorno, no una identidad física.

La fuente `06` actual aplica la revocación de `EXECUTE` por defecto sin `IN SCHEMA` para las funciones futuras del rol que ejecuta el script, en todos los esquemas de esa base. No se refiere al creador de la base ni se hereda automáticamente a otros creadores de funciones. También revoca explícitamente el helper creado después; no quedan FAIL de ACL en esta ejecución. Los campos `OLD`/`NEW`, IP, estación y `application_name` pueden contener datos sensibles; su exposición debe limitarse a los roles y finalidad definidos.

## Propuesta de privilegios por defecto (validación transaccional)

La propuesta de privilegios por defecto quedó incorporada en la fuente `06` actual: se revoca `EXECUTE` global por defecto para el creador y se aplica revocación explícita al helper creado después. La ejecución integrada terminó con 240 PASS, 0 FAIL y 0 BLOCKED; no se mezclan aquí los resultados históricos 62/4/23.

La sentencia correcta para el rol creador es `ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`, sin `IN SCHEMA`. PostgreSQL documenta que esta configuración afecta las funciones futuras creadas por ese propietario en todos los esquemas de la base; por ello no debe aplicarse sin revisar el alcance ni el propietario dedicado. La alternativa de menor alcance es revocar explícitamente en cada `CREATE FUNCTION` y conceder `EXECUTE` solo a los roles necesarios dentro de la misma transacción. Véase [ALTER DEFAULT PRIVILEGES en PostgreSQL 18](https://www.postgresql.org/docs/18/sql-alterdefaultprivileges.html), especialmente las reglas de alcance y privilegios de funciones.

Referencias: [CREATE FUNCTION](https://www.postgresql.org/docs/18/sql-createfunction.html), [Privileges](https://www.postgresql.org/docs/18/ddl-priv.html) y [Access privilege inquiry functions](https://www.postgresql.org/docs/18/functions-info.html), PostgreSQL 18.
