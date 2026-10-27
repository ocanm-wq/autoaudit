# Pruebas de AutoAudit

La ejecución backend controlada del 26/10/2026 usó `03` real en Ubuntu 26.04.1 LTS con PostgreSQL 18.6: **240 PASS, 0 FAIL y 0 BLOCKED**. La evidencia está en `tests/resultados/20261026_backend_controlado/`. La interfaz integrada obtuvo **38 PASS, 0 FAIL y 0 BLOCKED** por HTTP y **35 PASS, 0 FAIL y 0 BLOCKED** en SQL09; su evidencia está en `tests/resultados/20261026_interfaz/`. La corrida previa 236/4 queda excluida por mediciones negativas inválidas.

## Requisitos e interpretación

Usar una base **nueva** llamada `autoaudit_test` o `autoaudit_test_<sufijo>`, dentro de un **clúster dedicado y desechable**. El nombre no garantiza aislamiento: los roles PostgreSQL pertenecen al clúster. Ejecutar como dueño/superusuario de ese entorno, nunca sobre datos reales ni un clúster de producción.

El ejecutor utiliza Python estándar y psql, sin paquetes adicionales. Desde la raíz del repositorio:

```bash
python tests/run_tests.py --database autoaudit_test --confirmar-cluster-aislado
```

La base debe estar recién creada. `--psql "ruta/al/psql"` permite especificar el ejecutable; libpq utiliza `PGHOST`, `PGPORT`, `PGUSER` y la autenticación local configurada. No guardar contraseñas en el repositorio ni en comandos. `--confirmar-cluster-aislado` declara una precondición que debe ser verdadera, no crea aislamiento.

El ejecutor instala directamente `01`, `05` y `06`, sin reparar ni omitir sentencias. Si `03` tiene contenido lo instala; si sigue vacío registra BLOCKED. De `07` instala la definición y revocación de la función, y prepara la copia `07_solo_definicion.sql`; los ejemplos de la fuente actual también están comentados. Después ejecuta las suites, conserva logs y JSON, y compara conteos, objetos residuales y hashes SQL antes/después.

Código de salida de Python: `0` sin fallos ni bloqueos, `1` con algún fallo, `2` con bloqueos y sin fallos. La ejecución integrada vigente terminó con código `0`, sin fallos ni bloqueos. Un rechazo previsto solo cuenta como PASS si devuelve el SQLSTATE esperado.

## Entorno Ubuntu 26.04 probado

Desde la raíz, ejecutar las líneas por separado y esperar a que `pg_isready` confirme disponibilidad:

```bash
docker build -f tests/entorno/Dockerfile.ubuntu26 -t autoaudit-test-ubuntu26:local tests/entorno
docker run -d --name autoaudit-test-ubuntu26 --network none --memory 1g --cpus 2 --tmpfs /var/lib/postgresql:rw,size=768m autoaudit-test-ubuntu26:local
docker exec autoaudit-test-ubuntu26 pg_isready -U postgres
docker exec autoaudit-test-ubuntu26 createdb -U postgres autoaudit_test
python3 tests/run_tests.py --database autoaudit_test --docker-container autoaudit-test-ubuntu26 --confirmar-cluster-aislado
```

Elegir un nombre nuevo si el contenedor ya existe, y pasar ese mismo nombre al ejecutor. `PGHOST=/tmp` está definido en la imagen. No se publica ningún puerto ni se montan datos del anfitrión. El servidor solo escucha en un socket Unix; la autenticación local trust se limita a este contenedor sin red.

Si Docker reside dentro de WSL y la distribución se detiene al cerrar sus procesos, mantener otro terminal con `docker wait autoaudit-test-ubuntu26` mientras se ejecutan las pruebas. La construcción requiere descargar paquetes oficiales; el contenedor de pruebas se ejecuta sin red. Las versiones exactas observadas y el límite de compartir kernel con WSL figuran en `docs/VALIDACION_ENTORNO.md`.

Tras conservar la evidencia, retirar solo el contenedor creado para estas pruebas:

```bash
docker stop autoaudit-test-ubuntu26
docker rm autoaudit-test-ubuntu26
```

El tmpfs se descarta. La imagen local puede conservarse para repetir la validación. El tmpfs y los límites de CPU/RAM deben declararse si más adelante se obtienen tiempos; no representan medición de discos físicos.

## DBeaver

1. Conectarse a la base nueva del clúster dedicado; comprobar `SELECT current_database(), version();`.
2. Ejecutar con Alt+X, una sola vez y en este orden: `sql/01_estructura_autoaudit.sql`, `sql/03_generador_triggers.sql`, `sql/05_consultas_historial.sql`, `sql/06_seguridad.sql`, `sql/07_pruebas_rendimiento.sql`. Los ejemplos de `07` están comentados, por lo que instalarlo no ejecuta cargas.
3. `04` es una prueba manual opcional; puede ejecutarse después de instalar `03`. `02` es un conjunto de consultas de diccionario, con parámetros DBeaver; no es una instalación pendiente. Después de instalar `03`, ejecutar `06` antes de las suites para proteger sus funciones.
4. En la misma conexión, cargar `tests/00_comun.sql` una vez y ejecutar completas `tests/10_funcionales.sql`, `tests/20_seguridad.sql` y `tests/performance/30_rendimiento.sql`.
5. Cada suite calcula una tabla PASS/FAIL/BLOCKED y mensajes `AA_RESULT`/`AA_SUMMARY`. No hay que deducir resultados mirando filas de bitácora. Mantener BEGIN/ROLLBACK y no confirmar esas transacciones. Ante un error SQL inesperado, ejecutar ROLLBACK antes de seguir.

Una conexión nueva pierde las funciones temporales y exige volver a cargar `00_comun.sql`. No volver a cargar el común si ya existe en esa conexión; abrir una nueva si es necesario.

## psql con la base ya preparada

Cada línea carga el común en su propia conexión:

```bash
psql -X -v ON_ERROR_STOP=1 -d autoaudit_test -f tests/00_comun.sql -f tests/10_funcionales.sql
psql -X -v ON_ERROR_STOP=1 -d autoaudit_test -f tests/00_comun.sql -f tests/20_seguridad.sql
psql -X -v ON_ERROR_STOP=1 -d autoaudit_test -f tests/00_comun.sql -f tests/performance/30_rendimiento.sql
```

Las suites notifican fallos semánticos y continúan hasta ROLLBACK. `ON_ERROR_STOP` detecta errores SQL, pero una fila FAIL no cambia por sí sola la salida de psql; para automatización con código global fiable, utilizar `run_tests.py`.

## Rendimiento y correcciones

El wrapper prepara 100, 1.000 y 10.000 filas, tres repeticiones y un calentamiento descartado. Solo ejecuta las mediciones si existe el generador real. Para 100.000 hace falta `--incluir-100000` o, en DBeaver, `SET autoaudit_test.incluir_100000='on';` antes de la suite. No se habilitó ni ejecutó en esta revisión.

Las correcciones de historial y ACL ya están incorporadas en las fuentes `05` y `06`. `tests/patches/` conserva la propuesta original como referencia histórica: **no aplicar `05_quitar_q.patch` a la fuente actual**. El script de ACL de esa carpeta aún permite comprobar la misma política dentro de una transacción revertida, pero no es un paso necesario de instalación.

## Suites finales de la interfaz

`40_interfaz.sql` usa `00_comun.sql` y una transacción que revierte sus fixtures. Se ejecuta después de cargar 01, 03, 05, 06, 07 como definición, 08 A/B y 09 en un clúster desechable. La base debe llamarse `autoaudit_test` o `autoaudit_test_<sufijo>`.

```bash
psql -X -U postgres -d autoaudit_test_interfaz -v ON_ERROR_STOP=1 -f tests/40_interfaz.sql
python tests/test_consultas_http.py --url http://127.0.0.1:18087 --database autoaudit_test_http --container autoaudit-ui-20261026 --output tests/resultados/nueva_ejecucion_http --confirmar-cluster-aislado
```

El test HTTP necesita que PHP apunte a esa base aislada, instalada y con los 21 eventos de 08 A/B. Modifica solo su fixture `aa_http_casos` y lo limpia en `finally`. En Windows usa Docker dentro de WSL `Ubuntu-24.04`; en Linux llama a Docker directamente. El contenedor HTTP del laboratorio publicó PostgreSQL solo en `127.0.0.1:55426`; esa red es distinta del benchmark, que usa `--network none` y socket Unix. No ejecutar este test sobre la base de uso habitual.

Evidencia definitiva: backend 240/0/0 en `20261026_backend_controlado`, SQL09 35/0/0 en `20261026_interfaz`, HTTP 38/0/0 en `20261026_http_verificado` y navegador 29/0/0 en `20261026_interfaz/resultados_navegador.json`. Los demás intentos son históricos o diagnósticos. `capture_ui.cjs` conserva el guion exacto de capturas del laboratorio del 26 de octubre y sus rutas de runtime locales; no es requisito para utilizar la aplicación.
