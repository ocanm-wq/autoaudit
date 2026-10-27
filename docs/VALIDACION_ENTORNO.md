# Validación del entorno

La evidencia vigente de la suite está en `tests/resultados/20261025_integrado/`, incluido `resultados.json`; la demostración separada de `08` está en `tests/resultados/20261025_capturas/`.

- Host: Windows 11 Pro `10.0.22000`, x64; Ryzen 5 3600X, 6 núcleos/12 lógicos; RAM `17094459392` bytes.
- WSL: Ubuntu 24.04.4; kernel compartido `6.18.54.1-microsoft-standard-WSL2`.
- Docker `29.1.3`; imagen `autoaudit-test-ubuntu26:local`, SHA `a6c0d450232127999041286a670712748d56c15a7a01e6252b194b724b0f12e3`.
- Userland del contenedor: Ubuntu `26.04.1 LTS` (Resolute Raccoon).
- PostgreSQL: `18.6-0ubuntu0.26.04.1`, `x86_64-pc-linux-gnu`, GCC Ubuntu 15.2.0.
- Paquetes: `postgresql-18` y `postgresql-client-18`, ambos `18.6-0ubuntu0.26.04.1`.
- Contenedor: red `none`, memoria `1073741824` bytes (1 GiB), 2 CPU, tmpfs PostgreSQL de 768 MiB.

La ejecución controlada vigente del 26/10/2026 usa `autoaudit_test_20261026c` y reporta 240 PASS, 0 FAIL y 0 BLOCKED con `03` real. Usó `--network none`, 2 CPU, 1 GiB y tmpfs de 768 MiB. La corrida previa sin límites reportó 236/4 y se conserva excluida; los negativos observados se marcaron como mediciones inválidas, sin atribuir causa. Es userland Ubuntu 26.04.1 dentro de Docker; el kernel sigue siendo el compartido de WSL2, no un kernel Ubuntu independiente. La interfaz HTTP integrada reporta 38 PASS, 0 FAIL y 0 BLOCKED; la suite SQL09 reporta 35 PASS, 0 FAIL y 0 BLOCKED.

La compatibilidad SQL y dependencias se validó con esta ejecución. La evidencia anterior `20261023_revision_final` corresponde a un diagnóstico previo con Alpine y no sustituye esta ejecución Ubuntu.

## Receta opcional nativa

Si se desea repetir fuera de Docker, usar un clúster dedicado y no tocar producción:

```bash
sudo apt update
sudo apt install postgresql-18 postgresql-client-18 python3
sudo pg_createcluster 18 autoaudit_test -p 55432 --start
sudo -u postgres createdb -p 55432 autoaudit_test
sudo -u postgres env PGPORT=55432 python3 /ruta/al/repositorio/autoaudit/tests/run_tests.py --database autoaudit_test --confirmar-cluster-aislado --output /tmp/autoaudit-resultados-nuevos
```

Comprobar antes que el clúster y puerto no existan, usar loopback y hacer legible la ruta al usuario `postgres`. Los roles PostgreSQL son globales al clúster; por eso cambiar solo el nombre de la base no aísla permisos. Las instrucciones actuales de Docker y DBeaver están en `tests/README.md`.
