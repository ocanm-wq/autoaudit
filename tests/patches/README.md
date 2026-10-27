# Referencias de la revisión inicial

Las correcciones ya se incorporaron localmente en `sql/05_consultas_historial.sql` y `sql/06_seguridad.sql` por petición del usuario. Estos archivos conservan la propuesta inicial y no son pasos adicionales de instalación.

- `05_quitar_q.patch`: cambio histórico ya aplicado. No volver a aplicarlo a la fuente actual.
- `06_privilegios_propuestos.sql`: demostración transaccional de la política ya incorporada en 06. Requiere el común y una base aislada; finaliza con ROLLBACK. No se necesita para instalar el proyecto actual.

La evidencia anterior en `tests/resultados/20261023_revision_final/` describe el diagnóstico antes de reparar las fuentes. La evidencia vigente es `tests/resultados/20261023_ubuntu26_corregido/`.
