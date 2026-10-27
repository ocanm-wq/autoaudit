# Metodología de rendimiento

`tests/performance/30_rendimiento.sql` envuelve `auditoria.medir_rendimiento(n)` sin duplicar su medición. Ejecuta tres repeticiones por operación para 100, 1.000 y 10.000 filas. El volumen 100.000 sólo se ejecuta cuando `autoaudit_test.incluir_100000` vale `on`. Un calentamiento opcional de 100 filas se descarta y no entra en los promedios; si falla, el caso se marca como fallo.

Cada invocación debe devolver exactamente tres filas (`INSERT`, `UPDATE`, `DELETE`) y `n` filas. Los eventos esperados son 2n, n y 2n, respectivamente. Se verifica que los tiempos sean no negativos, que no queden las tablas `t_rend_sin`/`t_rend_con`, y que la configuración y las siete tablas de auditoría no acumulen residuos. La ejecución vigente usa `auditoria.generar_trigger(integer)` real; no se simula el generador.

El resultado `AA_BENCH_RAW` conserva cada muestra con la precisión original (0,1 ms), y `AA_BENCH` reporta promedio, desviación estándar muestral, mínimo, máximo, coeficiente de variación y sobrecosto. El sobrecosto se deja `NULL` cuando el denominador es cero; el resumen recalcula sobre los valores reportados y puede diferir del sobrecosto redondeado por la función. Casos sin tres muestras no se consideran PASS. La suite corre dentro de `BEGIN` y termina con `ROLLBACK`; las secuencias pueden avanzar y no se afirma que vuelvan a cero.

La función 07 usa `clock_timestamp()`, revierte datos mediante la subtransacción AU001 y conserva deltas de bitácora; las secuencias pueden avanzar. Su resultado no afirma un baseline independiente de cero para la rama sin auditoría. El wrapper añade aserciones, usa nombres internos controlados con `%I` y ejecuta el generador real. El orden fijo sin auditoría y luego con auditoría introduce sesgo; no se incluye commit, latencia del cliente ni TCP. El redondeo a 0,1 ms puede distorsionar ratios en `n=100`; tres repeticiones son insuficientes para inferencias fuertes. Los ejemplos de 100.000 siguen comentados y requieren habilitación manual.

La evidencia vigente está en `tests/resultados/20261026_backend_controlado/30_rendimiento.log` y `resultados.json`: Ubuntu 26.04.1 con PostgreSQL 18.6, 240 PASS, 0 FAIL y 0 BLOCKED. Se midieron 100, 1.000 y 10.000 filas, tres repeticiones por operación, con promedios, mínimo, máximo, desviación estándar, CV y sobrecosto. Los tiempos y porcentajes están sujetos al redondeo de 0,1 ms; no se ejecutó 100.000. El resultado valida el userland del contenedor, no el arranque del kernel de una VM Ubuntu 26.04.

## Mediciones controladas del 26 de octubre de 2026

Promedios reales de tres repeticiones. Los valores sin auditoría muy pequeños amplifican los porcentajes; se conserva el detalle de cada muestra en el log y el JSON.

| Filas | Operación | Sin auditoría ms | Con auditoría ms | CV con auditoría % |
|---:|---|---:|---:|---:|
| 100 | DELETE | 0.1 | 6.8 | 1.7 |
| 100 | INSERT | 0.4 | 7.4 | 6.8 |
| 100 | UPDATE | 0.4 | 4.7 | 5.3 |
| 1000 | DELETE | 0.4 | 67.6 | 6.3 |
| 1000 | INSERT | 2.2 | 75.0 | 7.2 |
| 1000 | UPDATE | 3.3 | 45.1 | 3.4 |
| 10000 | DELETE | 3.8 | 778.2 | 12.4 |
| 10000 | INSERT | 28.8 | 743.5 | 4.9 |
| 10000 | UPDATE | 31.7 | 436.8 | 78.1 |

La corrida previa `20261026_backend` con 236 PASS y 4 FAIL queda excluida del análisis por tiempos negativos. El origen de esa discontinuidad de medición no quedó confirmado. La repetición controlada pasó todas las aserciones, pero el CV de 78,1 % en UPDATE de 10.000 filas limita la interpretación.
