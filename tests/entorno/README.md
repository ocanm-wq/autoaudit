# Entorno Ubuntu 26.04 para AutoAudit

`Dockerfile.ubuntu26` crea una imagen reproducible basada en la imagen oficial `ubuntu:26.04`. Instala PostgreSQL 18 y su cliente desde APT, certificados, locales y usa `C.UTF-8`. El binario de PostgreSQL 18 queda primero en `PATH` (`/usr/lib/postgresql/18/bin`). Python no se instala dentro de la imagen: el runner se ejecuta en el host y usa `docker exec`/`psql`.

La imagen arranca un clúster nuevo en `/var/lib/postgresql/autoaudit` como usuario `postgres`. El `CMD` inicializa el clúster una sola vez con `--auth-local=trust` y rechaza autenticación TCP (`--auth-host=reject`); después arranca PostgreSQL con `listen_addresses=''` y el socket Unix en `/tmp`. El contenedor debe ejecutarse sin red y sin publicar puertos. `PGDATA` queda definido en el entorno para que el runner pueda comprobar la ubicación.

Construcción desde la raíz del repositorio:

```bash
docker build -f tests/entorno/Dockerfile.ubuntu26 -t autoaudit-test-ubuntu26:local tests/entorno
```

Ejecución de un contenedor nuevo, sin red ni puertos publicados:

```bash
docker run -d --name autoaudit-test-ubuntu26 --network none --memory 1g --cpus 2 --tmpfs /var/lib/postgresql:rw,size=768m autoaudit-test-ubuntu26:local
docker exec autoaudit-test-ubuntu26 pg_isready -h /tmp -U postgres
docker exec autoaudit-test-ubuntu26 createdb -h /tmp -U postgres autoaudit_test
```

El `tmpfs` evita persistir datos de prueba en el host. El `CMD` corre como root solo para crear el directorio y ajustar propietario; `initdb` y `postgres` se ejecutan como `postgres`. La construcción requiere acceso a los repositorios oficiales; la ejecución del servidor no requiere red. El runner carga las fuentes locales del proyecto y guarda la evidencia fuera del contenedor.

Al terminar la evidencia, eliminar únicamente el contenedor creado:

```bash
docker stop autoaudit-test-ubuntu26
docker rm autoaudit-test-ubuntu26
```

La evidencia disponible corresponde a Ubuntu 26.04.1 y PostgreSQL 18.6 sobre Ubuntu. Esto valida el userland del contenedor; no constituye una validación del arranque del kernel de una VM Ubuntu 26.04. Si WSL necesita mantener vivo el contenedor, dejar otro terminal con `docker wait autoaudit-test-ubuntu26`.
