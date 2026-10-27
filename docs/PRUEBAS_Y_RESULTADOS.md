# AutoAudit: pruebas y resultados finales

## Estado actual

La ejecución backend final se realizó el 26/10/2026 sobre `autoaudit_test_20261026c`, con Ubuntu 26.04.1 y PostgreSQL 18.6, dentro de un contenedor con red `none`, socket Unix, 2 CPU, 1 GiB y tmpfs de 768 MiB.

Estado actual (26/10/2026): `tests/run_tests.py` en contenedor controlado produjo **240 PASS, 0 FAIL y 0 BLOCKED**. La evidencia está en `tests/resultados/20261026_backend_controlado/`. La ejecución del 25/10/2026 queda como histórico en `tests/resultados/20261025_integrado/`.

La suite instaló y probó `01`, `03`, `05`, `06` y la definición de medición de `07`. El runner no ejecuta `08_datos_demostracion.sql` como suite. `08` se verificó aparte en `tests/resultados/20261025_capturas/`, sobre `autoaudit_test_capturas`; esa evidencia no se suma al conteo 240/0/0.

Las fuentes proceden del commit `431451fede1b42e8ae56a3695878ab5f8a7f68ac`:

- `03`: `8f2c77f63603b8e6007d2fae923f1ef4f7a0cd2fb304e1adcf578c79c46e55a8`.
- `08`: `688d00077b93d8f3719a5b45a8af27e06c0be153b4781438798e5ccaa1baba81`.

## Resultado por grupo

| Grupo | PASS | FAIL | BLOCKED |
|---|---:|---:|---:|
| Instalación | 6 | 0 | 0 |
| Funcionales | 29 | 0 | 0 |
| Seguridad | 49 | 0 | 0 |
| Rendimiento | 153 | 0 | 0 |
| Limpieza e integridad | 3 | 0 | 0 |
| **Total** | **240** | **0** | **0** |

Las pruebas funcionales comprobaron INSERT, UPDATE y DELETE reales, OLD/NEW/NULL, usuario y fecha, columnas y tablas no auditadas, regeneración sin duplicados, validaciones de identificadores y rechazo de intentos de inyección. Seguridad comprobó roles, ACL, `SECURITY DEFINER`, `search_path`, permisos de generación/eliminación y protección de la bitácora.

## Rendimiento

`tests/resultados/20261026_backend_controlado/30_rendimiento.log` contiene tres repeticiones por operación para 100, 1.000 y 10.000 filas, con tiempos sin/con auditoría, promedio, mínimo, máximo, desviación estándar, CV, sobrecosto y cardinalidad de eventos. No se ejecutó 100.000. Las cifras están sujetas al redondeo de 0,1 ms y no incluyen latencia de cliente ni commit de red.

La medición se realizó dentro del contenedor sin red y no representa discos físicos ni producción. La evidencia de `08` y la prueba TCP de capturas son demostraciones separadas; no forman parte del benchmark.

## Entorno y privacidad

El userland Ubuntu 26.04.1 fue validado dentro de Docker/WSL2. El kernel es el compartido por WSL2; no se afirma el arranque de una VM Ubuntu independiente.

La suite principal usó socket Unix, por lo que la IP observada puede ser `NULL`. `20261025_capturas` usa un clúster de demostración con TCP restringido a `127.0.0.1:55425`; documenta captura de demostración y conectividad, no cambia el benchmark. TCP no debe presentarse como validado para todos los despliegues.

Los roles pueden consultar IP, estación y valores OLD/NEW según sus permisos. NAT, proxies y `application_name` limitan la atribución de identidad. Retención, anonimización y vista sin IP siguen siendo decisiones institucionales.

## Históricos y límites

`tests/resultados/20261023_revision_final/` y `tests/resultados/20261023_ubuntu26_corregido/` son históricos: conservaron 62/4/23 y 64/0/23. No se suman con la ejecución final.

La interfaz PHP Sneat está integrada y se validó por HTTP y navegador. La suite SQL de apoyo a la interfaz obtuvo **35 PASS, 0 FAIL y 0 BLOCKED** en `tests/resultados/20261026_interfaz/`; la evidencia visual final está en `docs/capturas_interfaz/` y la guía final en `docs/AutoAudit_Guia_Interfaz_Final.pdf`.

La ejecución backend controlada del 26/10/2026 obtuvo **240 PASS, 0 FAIL y 0 BLOCKED** con Ubuntu 26.04.1, PostgreSQL 18.6, `--network none`, 2 CPU, 1 GiB y tmpfs de 768 MiB. La corrida previa sin esos límites produjo 236/4; se conserva como diagnóstico excluido. Sus tiempos negativos cercanos a -9.5 s se consideran mediciones inválidas; no se atribuye una causa sin evidencia adicional. En la corrida controlada el volumen 10.000 mostró alta variación en UPDATE (CV 78.1%). El volumen 100.000 no se ejecutó.

## Repetición

En una base nueva y un clúster desechable:

```bash
python tests/run_tests.py --database autoaudit_test --confirmar-cluster-aislado
```

La evidencia backend actual está en `tests/resultados/20261026_backend_controlado/resultados.json`; la demostración de `08` y capturas está en `tests/resultados/20261025_capturas/`.

## Integración de la interfaz el 26 de octubre

| Suite final | PASS | FAIL | BLOCKED | Evidencia |
|---|---:|---:|---:|---|
| SQL09 | 35 | 0 | 0 | `20261026_interfaz/resultados_sql09.json` |
| HTTP con fixtures y CSV | 38 | 0 | 0 | `20261026_http_verificado/resultados.json` |
| Chrome y navegación real | 29 | 0 | 0 | `20261026_interfaz/resultados_navegador.json` |

Las rutas parten de `tests/resultados/`. HTTP comprobó paginación 25/50/100 sobre 68 eventos temporales, CSV completo, NULL, cadena vacía, fórmulas, HTML escapado, fechas y parámetros inválidos. La limpieza devolvió el fixture a sus 21 eventos de demostración. Chrome comprobó el enlace Ver historial y desactivar/reactivar auditoría además de roles, filtros y descarga. Las 15 capturas y sus SHA256 se registran en `capturas_manifest.json`.

Los intentos previos `20261026_http`, `20261026_http_final` y `20261026_http_revisado`, así como `diagnostico_selector_navegacion.json`, se conservan como diagnósticos de preparación o automatización. El último incluyó un nombre de campo incorrecto en una consulta del test; se corrigió el test a la columna real `tabla` de la vista. El selector del navegador se ajustó al nombre accesible con icono. Estos intentos no se presentan como ejecuciones finales aprobadas.
