# Matriz de pruebas funcionales

Ejecución vigente del 26/10/2026 en base `autoaudit_test_20261026c` (Ubuntu 26.04.1): las suites integradas produjeron 240 PASS, 0 FAIL y 0 BLOCKED.

Las consultas se probaron con semillas explícitas y comparación bidireccional `EXCEPT ALL`; además, los casos DML integrados comprobaron la captura real por triggers de `03`.

| ID real de la suite | Estado observado | Condición o dependencia |
|---|---|---|
| `catalogo_eventos` | PASS | Catálogo exactamente INSERT, UPDATE y DELETE en su orden de IDs. |
| `columna_fk` | PASS | 23503: insert or update on table "aud_columna" violates foreign key constraint "aud_columna_id_tabla_fkey" |
| `config_desactivada` | PASS | Evento desactivado no añade bitácora tras regenerar. |
| `config_fk_columna` | PASS | 23503: insert or update on table "aud_configuracion" violates foreign key constraint "aud_configuracion_id_columna_fkey" |
| `config_fk_evento` | PASS | 23503: insert or update on table "aud_configuracion" violates foreign key constraint "aud_configuracion_id_evento_fkey" |
| `config_not_null` | PASS | 23502: null value in column "id_columna" of relation "aud_configuracion" violates not-null constraint |
| `config_unique` | PASS | 23505: duplicate key value violates unique constraint "aud_configuracion_id_columna_id_evento_key" |
| `consulta_columna` | PASS | Multiset exacto de correo; excluye nombre. |
| `consulta_limites_temporales` | PASS | Desde inclusivo y hasta exclusivo. |
| `consulta_objeto_invalido` | PASS | Filtro inexistente devuelve conjunto vacío. |
| `consulta_registro` | PASS | Multiset exacto de 9001; excluye el registro 9002. |
| `consulta_usuario` | PASS | Multiset exacto del usuario; excluye las filas de otro usuario. |
| `dml_eliminado_consultable` | PASS | Fuente eliminada y cinco cambios todavía consultables. |
| `dml_identidad_fecha` | PASS | Usuario y fecha del cambio dentro del intervalo de ejecución. |
| `dml_multiset_exacto` | PASS | Cinco cambios exactos: INSERT 2, UPDATE 1 y DELETE 2; OLD/NEW, columna e ID. |
| `dml_no_auditada` | PASS | Cambiar teléfono no añade eventos. |
| `dml_null` | PASS | Transiciones correo x → NULL → y. |
| `dml_regeneracion_sin_duplicados` | PASS | Un trigger y dos eventos por inserción después de regenerar dos veces. |
| `dml_update_sin_cambio` | PASS | Actualizar un valor a sí mismo no añade eventos. |
| `evento_check` | PASS | 23514: new row for relation "aud_evento" violates check constraint "aud_evento_nombre_check" |
| `evento_unique` | PASS | 23505: duplicate key value violates unique constraint "aud_evento_pkey" |
| `generador_columna_invalida` | PASS | Rechazo verificable de columna inexistente. |
| `generador_config_id_invalido` | PASS | Rechazo verificable de ID inexistente. |
| `generador_inyeccion` | PASS | Identificador con comillas y sentencia inocua de prueba; centinela conservado. |
| `generador_tabla_invalida` | PASS | Rechazo verificable de esquema/tabla inexistente. |
| `tabla_desactivada` | PASS | Tabla desactivada no añade bitácora tras regenerar. |
| `tabla_unique` | PASS | 23505: duplicate key value violates unique constraint "aud_tabla_esquema_nombre_tabla_key" |

Los IDs `dml_ejecucion` y `generador_inyeccion_rechazo` son señales adicionales de las ramas integradas. Los contratos admitidos de error están declarados en los arreglos SQLSTATE; otros errores producen FAIL. Estos casos pasaron con el generador real; la evidencia está en `tests/resultados/20261026_backend_controlado/`.

La comparación de usuario actualmente prepara una sesión de dueño. La integración PHP posterior verificó conexiones reales de las cuentas demo y sus restricciones en SQL09, HTTP y Chrome. El comportamiento bajo concurrencia no se midió. Consulte PRUEBAS_Y_RESULTADOS.md para los resultados de esas suites separadas.
