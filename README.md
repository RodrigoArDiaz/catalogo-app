# Catálogo App

Aplicación desarrollada como trabajo práctico durante el cursado del curso "Contenedores, Docker y Orquestación con Kubernetes"

El proyecto está compuesto por dos aplicaciones:

- `backend/`: API y lógica del servidor.
- `frontend/`: aplicación cliente.

## Repositorios originales

Backend:
https://github.com/aanzorena/app-catalogo-backend

Frontend:
https://github.com/aanzorena/app-catalogo-frontend

## Arquitectura
navegador ──► catalogo-frontend ──────► catalogo-api ──────► catalogo-db
React + Vite Python + FastAPI MongoDB 7
nginx :8080 :8000 :27017
(host 3000) (host 8000, solo (sin puerto
depuración) publicado)

| Capa | Imagen | Puerto interno | Puerto publicado |
| --- | --- | --- | --- |
| `catalogo-frontend` | React + Vite servido por nginx | 8080 | 3000 |
| `catalogo-api` | Python + FastAPI | 8000 | 8000 (solo depuración) |
| `catalogo-db` | MongoDB 7 | 27017 | — |
El frontend es el único punto de entrada: nadie le habla a la base
directamente, y a la API le habla el frontend.


### MongoDB - authSource (Trabajo Practico Nº 1 - Ejercicio 6)

El usuario inicial configurado mediante `MONGO_INITDB_ROOT_USERNAME` y
`MONGO_INITDB_ROOT_PASSWORD` se crea en la base `admin`.

Por este motivo, la cadena de conexión de la aplicación debe especificar:

mongodb://catalogo_user:catalogo_pass@catalogo-db:27017/catalogo?authSource=admin

Sin `authSource=admin`, MongoDB intenta autenticar al usuario contra la base
`catalogo` y la autenticación falla.



## Comparación de imágenes (Trabajo Practico Nº 2 - Ejercicio 8)

Se utiliza la columna DISK USAGE de Docker, tomando 1.71 GB como 1710 MB.
Los porcentajes son aproximados porque los tamaños mostrados están redondeados.

| Imagen | Base final | Tamaño | Reducción respecto de API ingenua |
|---|---|---:|---:|
| catalogo-api:ingenua | python:3.12 | 1710 MB | — |
| catalogo-api:v1 | python:3.12-slim | 258 MB | 84.91 % |
| catalogo-api:v2 | python:3.12-slim | 258 MB | 84.91 % |
| catalogo-frontend:v1 | nginxinc/nginx-unprivileged:1.27-alpine | 73.9 MB | 95.68 % |

Fórmula: reducción (%) = (1 − tamaño final / tamaño ingenuo) × 100.

El porcentaje del frontend es una comparación de tamaño entre componentes
distintos; no representa una optimización de la misma aplicación.

### Aporte de cada decisión (Trabajo Practico Nº 2 - Ejercicio 8)

- Multi-etapa en la API: permite copiar las dependencias instaladas a una imagen final sin incorporar toda la etapa de construcción.
- python:3.12-slim: reduce el tamaño de la base utilizada para ejecutar la API.
- pip install --user: agrupa las dependencias en un directorio que se puede copiar entre etapas.
- pip --no-cache-dir: evita guardar la caché de descargas en el builder; esa caché tampoco se transfiere a la imagen final.
- Manifiestos antes del código: permite reutilizar la capa de dependencias cuando solo cambia el código, reduciendo el tiempo de reconstrucción.
- .dockerignore: excluye archivos locales innecesarios del contexto y de las instrucciones COPY.
- Multi-etapa en el frontend: deja únicamente los archivos compilados y Nginx, sin Node, npm, node_modules ni código fuente.
- Usuarios sin privilegios: limitan los permisos del proceso durante la ejecución.
- ARG y ENV para APP_VERSION: permiten definir la versión durante el build y consultarla al ejecutar el contenedor.

## Análisis de capas de la API (Trabajo Practico Nº 2 - Ejercicio 9)

Se inspeccionó catalogo-api:v1 con docker history, excluyendo las capas de 0B.

La capa de mayor tamaño ocupa 87.6 MB y corresponde al sistema base Debian,
heredado de python:3.12-slim. Entre las capas agregadas por nuestro Dockerfile,
la mayor ocupa 53 MB y corresponde a las dependencias de Python copiadas desde
/root/.local del builder hacia /home/appuser/.local de la etapa final.
El código de la aplicación aporta solamente 557 kB.

## Cache - (Trabajo Practico Nº 2 - Ejercicio 10)

Al modificar únicamente el código, la instalación de dependencias se reutiliza desde el caché porque requirements.txt se copia e instala antes que el código.
Al modificar requirements.txt, se invalida su capa de COPY y el RUN de instalación que depende de ella, por lo que pip install vuelve a ejecutarse.

## Publicación en Docker Hub - (Trabajo Practico Nº 2 - Ejercicio 11)

Imágenes publicadas:

- diazrodrigoar/catalogo-api:v1
- diazrodrigoar/catalogo-api:v2
- diazrodrigoar/catalogo-frontend:v1

 catalogo-api: https://hub.docker.com/repository/docker/diazrodrigoar/catalogo-api

 catalogo-frontend: https://hub.docker.com/repository/docker/diazrodrigoar/catalogo-frontend

Se utilizó docker login para autenticarse, docker tag para agregar el
prefijo del usuario y docker push para subir las imágenes al registry.

## Contenedor catalogo-db (Trabajo Practico Nº 3 - Ejercicio 2)

```bash
docker run -d \
  --name catalogo-db \
  --network catalogo-net \
  -e MONGO_INITDB_ROOT_USERNAME=catalogo_user \
  -e MONGO_INITDB_ROOT_PASSWORD=catalogo_pass \
  -v catalogo-db-data:/data/db \
  mongo:7
```

Salida:

```
be7a7f70d351eee26bf2df02163aa1665b1eee87c57c0edb28c815389a1b6b25
```

```bash
docker ps --filter name=catalogo-db
```

```
CONTAINER ID   IMAGE     COMMAND                  CREATED         STATUS         PORTS       NAMES
be7a7f70d351   mongo:7   "docker-entrypoint.s…"   4 minutes ago   Up 4 minutes   27017/tcp   catalogo-db
```

Línea del registro que informa que el motor se encuentra a la espera de conexiones:

```
{"t":{"$date":"2026-10-08T20:43:48.400+00:00"},"s":"I",  "c":"NETWORK",  "id":23016,   "ctx":"listener","msg":"Waiting for connections","attr":{"port":27017,"ssl":"off"}}
```

### Justificación de la ausencia de `-p`

La base de datos es la capa más interna del stack: solo la API (`catalogo-api`)
necesita conectarse a ella, y ambos contenedores comparten la red `catalogo-net`.
Publicar el puerto 27017 en el anfitrión expondría MongoDB fuera de esa red sin
necesidad. Al omitir `-p`, el motor solo es alcanzable por nombre (`catalogo-db`)
desde los contenedores conectados a `catalogo-net`.

## Dos modos de falla del motor (Trabajo Practico Nº 3 - Ejercicio 4)

### Explicación

Con `DB_HOST=catalogo-bd` (nombre mal escrito), el cliente no resuelve el host en
la red Docker: el fallo ocurre antes de contactar a MongoDB, por eso el registro
habla de resolución de nombre y no de credenciales incorrectas.

Con `mongosh` sin `?authSource=admin`, la conexión sí llega al servidor
(`catalogo-db` resuelve), pero MongoDB intenta autenticar al usuario contra la
base `catalogodb` en lugar de `admin`, donde fue creado con
`MONGO_INITDB_ROOT_*`; por eso el mensaje es de autenticación fallida.

## Frontend fuera de la red (Trabajo Practico Nº 3 - Ejercicio 5)

### Explicación

El frontend se inició en la red bridge predeterminada porque se omitió
`--network catalogo-net`, por lo que no pudo resolver el nombre `catalogo-api`.
Nginx intenta resolver el upstream al arrancar y, al fallar, termina con código 1
en lugar de iniciar y reintentar.

## Frontend en catalogo-net (Trabajo Practico Nº 3 - Ejercicio 6)

Al crear un producto con imagen desde `http://localhost:3000`, la petición POST
aparece en la pestaña Network como `http://localhost:3000/api/productos` (mismo
origen). No hay llamadas directas a `localhost:8000`: el navegador habla con nginx
y nginx reenvía al backend por la red Docker.

No se observan solicitudes OPTIONS: al pasar por el proxy de nginx no hay CORS
entre orígenes distintos, porque la API se consume bajo el mismo host y puerto
que la aplicación web.

## Proxy y ROOT_PATH (Trabajo Practico Nº 3 - Ejercicio 7)

### Explicación

Con `ROOT_PATH=/api`, FastAPI incluye el prefijo en `openapi.json`
(`servers: [{url: "/api"}]`) y Swagger genera URLs relativas a `/api/...`, que
coinciden con el proxy. Sin `ROOT_PATH`, las URLs se generan desde la raíz
(`/productos`, `/docs`, etc.); a través del proxy en `localhost:3000/api/docs`
esas rutas no existen y la interfaz no carga.

## Orden de arranque (Trabajo Practico Nº 3 - Ejercicio 9)

El orden es: **Red → Volumen → Base de datos → API → Frontend**

| Paso | Motivo y consecuencia de alterar el orden |
| --- | --- |
| 1. Red `catalogo-net` | Debe existir antes de iniciar contenedores con `--network catalogo-net`. Si no existe, Docker falla con `network catalogo-net not found`. |
| 2. Volumen `catalogo-db-data` | Se crea para almacenar los datos de MongoDB. Si no se crea antes, `docker run -v` lo crea automáticamente: invertir este paso no necesariamente genera un error. |
| 3. Base `catalogo-db` | Debe estar lista para aceptar conexiones antes de iniciar la API. Que el contenedor esté ejecutándose no significa que MongoDB haya terminado de inicializar. |
| 4. API `catalogo-api` | Si arranca antes de que la base esté disponible, falla la conexión y puede reintentar o fallar su inicialización. Si la base todavía no existe en la red, también puede fallar la resolución de su nombre. |
| 5. Frontend `catalogo-frontend` | Nginx necesita resolver `catalogo-api` al arrancar. Si ese nombre todavía no existe en la red, termina con `host not found in upstream`. Si el nombre resuelve pero la API aún no atiende, Nginx puede arrancar y devolver `502 Bad Gateway` al solicitar datos. |

### Limitación actual

Hay que ejecutar los comandos en el orden correcto y comprobar cuándo está listo
cada servicio. Ese procedimiento todavía no está declarado en un archivo que
automatice el despliegue.

En la próxima etapa, Docker Compose permitirá declarar servicios, red, volumen y
dependencias. Para esperar a que una base esté realmente lista, se necesita un
healthcheck y una dependencia condicionada a ese estado; el orden de inicio por
sí solo no garantiza disponibilidad.

## Healthcheck de catalogo-db (Trabajo Practico Nº 4 - Ejercicio 2)

```yaml
healthcheck:
  test:
    - CMD-SHELL
    - mongosh --quiet --eval "db.adminCommand('ping').ok" || exit 1
  interval: 5s
  timeout: 3s
  retries: 10
  start_period: 10s
```

### Por qué no lleva credenciales

`db.adminCommand('ping')` es un comando administrativo que MongoDB acepta sin
autenticación: solo comprueba que el motor responda en el puerto 27017. El
cliente `mongosh` ya viene incluido en la imagen `mongo:7`, por lo que no hace
falta instalar dependencias adicionales.

En la variante B (PostgreSQL), el healthcheck equivalente es
`pg_isready -U notas_user -d notasdb`, que requiere indicar el usuario y, en la
práctica, la contraseña viaja en el comando o en variables visibles para el
proceso del healthcheck. Eso implica que la credencial queda expuesta en la
definición del servicio, en `docker inspect` y en los logs del daemon. En
MongoDB, `ping` evita ese problema: el chequeo de salud no necesita conocer
`catalogo_user` ni `catalogo_pass`.

### Qué no verifica

Que `ping` responda con éxito no prueba que el usuario `catalogo_user` exista,
ni que la contraseña configurada en `MONGO_INITDB_ROOT_PASSWORD` sea la correcta,
ni que la base `catalogodb` esté accesible con autenticación. Solo confirma que
el servidor MongoDB acepta conexiones. La API puede fallar igualmente con
`Authentication failed` aunque Compose declare el servicio como `healthy` — por
ejemplo, si el volumen ya fue inicializado con otra contraseña o falta
`authSource=admin` en la cadena de conexión.

## Healthcheck de catalogo-api (Trabajo Practico Nº 4 - Ejercicio 3)

```yaml
healthcheck:
  test:
    - CMD
    - python
    - -c
    - "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"
```

### Por qué no instalar curl solo para el healthcheck

La imagen `catalogo-api:v1` ya incluye Python; el módulo `urllib` forma parte de la
biblioteca estándar y permite hacer un GET a `/health` sin agregar paquetes al
Dockerfile. Instalar `curl` solo para el healthcheck implicaría una instrucción
`RUN apt-get install curl` (o equivalente) que agranda la imagen, invalida capas
en caché y añade una dependencia de sistema que la aplicación no usa en
runtime — contradice la optimización de tamaño practicada en el Trabajo Práctico
Nº 2. Además, si la respuesta no es 2xx, `urlopen` lanza excepción y el
proceso termina con código distinto de cero, que es justo lo que Docker necesita
para marcar el servicio como `unhealthy`.

## depends_on con condición (Trabajo Practico Nº 4 - Ejercicio 5)

```yaml
# catalogo-api
depends_on:
  catalogo-db:
    condition: service_healthy

# catalogo-frontend
depends_on:
  catalogo-api:
    condition: service_healthy
```

Los dos casos no son equivalentes:

### a) `catalogo-api` respecto de `catalogo-db`

La API debe conectarse a MongoDB y sembrar el catálogo al arrancar. La forma
corta `depends_on: [catalogo-db]` solo espera a que el contenedor de la base
entre en ejecución, no a que MongoDB acepte conexiones: el proceso puede estar
corriendo mientras el motor todavía se inicializa. Por eso se usa
`condition: service_healthy`, que espera a que el healthcheck de `catalogo-db`
(`mongosh` + `ping`) responda con éxito.

Además, la API reintenta la conexión durante unos 30 segundos
(`esperar_mongo` en `main.py`). Ese reintento es lo único que subsistirá en
Kubernetes, donde no existe `depends_on`: allí la API dependerá únicamente de
ese bucle de reconexión si arranca antes que la base.

### b) `catalogo-frontend` respecto de `catalogo-api`

Lo que no puede faltar es algún `depends_on` hacia la API. Sin él, el frontend
arranca antes que `catalogo-api`, nginx intenta resolver el upstream al iniciar
y termina con `host not found in upstream "catalogo-api"`.

A nginx le basta con que el nombre resuelva en la red Docker — la forma corta
`depends_on: [catalogo-api]` también evita ese fallo. `service_healthy` agrega
que la API ya esté respondiendo en `/health` antes de arrancar nginx, evitando
respuestas `502 Bad Gateway` en los primeros segundos mientras uvicorn todavía
está levantando.

## Diferencia entre `down` y `down -v`  (Trabajo Practico Nº 4 - Ejercicio 7)

`docker compose down` borra lo que el próximo `up` recrea igual: contenedores y
red. El volumen `catalogo-db-data` —declarado con `name:` explícito en el
compose— sobrevive con todos los documentos de MongoDB. Un `up` posterior
monta el mismo volumen y la base retoma el estado anterior.

`docker compose down -v` agrega la eliminación de los volúmenes declarados en
el archivo. Con `-v`, `catalogo-db-data` desaparece de `docker volume ls` y
el próximo `up` arranca MongoDB sobre un volumen vacío: se aplican de nuevo las
variables `MONGO_INITDB_*` y la API ejecuta la siembra del catálogo demo.

## Variables de entorno (Trabajo Practico Nº 4 - Ejercicio 9)

El contrato completo de variables está en [`.env.example`](.env.example), con
comentarios que indican qué componente consume cada una (`catalogo-db`,
`catalogo-api`, `catalogo-frontend`). Para levantar el stack con valores
locales:

```bash
cp .env.example .env
docker compose up -d
```

El archivo `.env` figura en [`.gitignore`](.gitignore) y no se versiona. Compose
interpola `${VAR}` desde `.env` al resolver `docker-compose.yml`.

La API acepta `MONGO_URI` como alternativa a `DB_HOST`, `DB_PORT`, `DB_NAME`,
`DB_USER` y `DB_PASSWORD`. Esa cadena incluye la contraseña en texto plano; en
Kubernetes (semana 7) debe ubicarse completa en un **Secret**, nunca en un
ConfigMap.

## Revisión de seguridad (Trabajo Practico Nº 4 - Ejercicio 10)

Comandos utilizados:

```bash
docker compose exec catalogo-api id
docker compose exec catalogo-frontend id
docker compose ps
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image catalogo-api:v1
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image catalogo-frontend:v1
```

### a) Usuario de ejecución

| Servicio | Comando | Usuario (uid) | ¿Distinto de root? |
| --- | --- | --- | --- |
| `catalogo-api` | `docker compose exec catalogo-api id` | `appuser` (uid 1000) | Sí — definido con `USER appuser` en el Dockerfile |
| `catalogo-frontend` | `docker compose exec catalogo-frontend id` | `nginx` (uid 101) | Sí — imagen `nginxinc/nginx-unprivileged` |
| `catalogo-db` | — | `mongodb` (uid 999) | Referencia — imagen oficial; arranca como root y baja de privilegios |

Salida esperada de las dos imágenes propias:

```
# catalogo-api
uid=1000(appuser) gid=1000(appuser) groups=1000(appuser)

# catalogo-frontend
uid=101(nginx) gid=101(nginx) groups=101(nginx)
```

### b) Puertos publicados (`docker compose ps`)

| Servicio | Puertos en `docker compose ps` | ¿Publicado en el host? |
| --- | --- | --- |
| `catalogo-db` | `27017/tcp` (sin flecha) | **No** — solo alcanzable desde `catalogo-net` |
| `catalogo-api` | `0.0.0.0:8000->8000/tcp` | Sí — solo depuración |
| `catalogo-frontend` | `0.0.0.0:3000->8080/tcp` | Sí — único punto de entrada |

### c) Puerto 8000 de la API

`catalogo-api` publica `8000:8000` únicamente para depurar con `curl` directo
(`localhost:8000/health`). En producción el navegador entra por
`localhost:3000/api/...` vía nginx. En la semana 6, al traducir el stack a
Kubernetes, ese puerto dejará de publicarse en el host y la API pasará a ser un
Service interno del clúster.

### d) Escaneo de vulnerabilidades (Trivy)

Comando (escaneos del 2026-10-15 y 2026-10-16; la primera corrida descarga la
base de datos de Trivy ~128 MB):

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image catalogo-api:v1

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image catalogo-frontend:v1
```

| Imagen | Origen | Hallazgos | Con parche (Fixed Version) |
| --- | --- | --- | --- |
| `catalogo-api:v1` | Sistema base (Debian 13.7, heredado de `python:3.12-slim`) | 166 · 0 CRITICAL, 44 HIGH, 58 MEDIUM, 61 LOW, 3 UNKNOWN | 1 |
| `catalogo-api:v1` | Dependencias Python (`pip`, `pymongo`, `starlette`) | 17 · 0 CRITICAL, 5 HIGH, 10 MEDIUM, 2 LOW | 17 |
| `catalogo-frontend:v1` | Sistema base (Alpine 3.21.3, `nginxinc/nginx-unprivileged:1.27-alpine`) | 159 · 2 CRITICAL, 39 HIGH, 76 MEDIUM, 42 LOW | 159 |

Desglose de las dependencias Python en `catalogo-api:v1`:

| Paquete | Hallazgos | Ejemplos con parche disponible |
| --- | --- | --- |
| `pip` 25.0.1 | 6 | actualizar a ≥ 26.1.2 |
| `pymongo` 4.8.0 | 4 | actualizar a ≥ 4.18.2 |
| `starlette` 0.38.6 | 7 | actualizar a ≥ 1.3.1 |

En el sistema base Debian de la API, casi ningún hallazgo trae *Fixed Version* en
Trivy (1 de 166: `liblzma5` → `5.8.1-1+deb13u2`); en cambio las 17 CVE de
Python sí indican versión corregida. En el frontend, los 159 hallazgos provienen
solo del sistema base Alpine (sin dependencias de aplicación escaneadas) y
todos tienen *Fixed Version* — por ejemplo OpenSSL 3.3.3-r0 → 3.3.7-r2,
BusyBox 1.37.0-r12 → 1.37.0-r14, zlib 1.3.1-r2 → 1.3.2-r1. Eso coincide con
el contraste del curso: en la API hay pocos parches aplicables hoy en el OS, pero
sí listados en pip/pymongo/starlette; en el frontend la base Alpine quedó vieja
y se arregla reconstruyendo sobre una imagen padre más nueva.

En la tabla de Trivy, la columna **Fixed Version** indica si existe versión
corregida. El objetivo no es llegar a cero CVE, sino saber qué hay y haber
decidido qué aceptar, mitigar o actualizar.

## Mínimo privilegio — `cap_drop: [ALL]` (Trabajo Practico Nº 4 - Ejercicio 11)

### Paso 1: quitar todas las capabilities

Se agregó `cap_drop: [ALL]` a los tres servicios en `docker-compose.yml`:

```yaml
cap_drop:
  - ALL
```

Comprobación:

```bash
docker compose up -d
docker compose ps
docker compose logs catalogo-db
```

Salida de `docker compose up -d`:

```
✔ Network catalogo-net    Created
✘ Container catalogo-db   Error dependency catalogo-db failed to start
✔ Container catalogo-api  Created
✔ Container catalogo-frontend Created
dependency failed to start: container catalogo-db exited (1)
```

`catalogo-api` y `catalogo-frontend` quedan en estado **Created** (no arrancan)
porque dependen de `catalogo-db` con `condition: service_healthy`. Las dos imágenes
propias están preparadas para funcionar sin capabilities extra — corren como
`appuser` y `nginx` (uid 101), no como root —; en este paso no alcanzan a
demostrarlo porque la base no levanta.

`catalogo-db` termina con código 1. Logs:

```
find: '/data/db/journal': Permission denied
find: '/data/db/diagnostic.data': Permission denied
find: '/data/db/.mongodb': Permission denied
```

Sin ninguna capability, el entrypoint de MongoDB no puede recorrer ni preparar
el directorio de datos en el volumen.

### Paso 2: `cap_add` de a una hasta `(healthy)`

Se fue agregando una capability por vez en `catalogo-db`, levantando de nuevo y
leyendo el error en cada paso:

| Orden | `cap_add` | Resultado |
| --- | --- | --- |
| 1 | `CHOWN` | Sigue fallando — aún no puede ignorar restricciones de dueño ni permisos DAC |
| 2 | `FOWNER` | Sigue fallando — falta bypass de permisos sobre archivos del datadir |
| 3 | `DAC_OVERRIDE` | Sigue fallando — el entrypoint puede preparar `/data/db`, pero no cambiar de usuario |
| 4 | `SETUID` | Sigue fallando — falta complemento para el cambio de identidad del proceso |
| 5 | `SETGID` | **`(healthy)`** — MongoDB arranca y acepta conexiones |

Configuración final de `catalogo-db`:

```yaml
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - FOWNER
  - DAC_OVERRIDE
  - SETUID
  - SETGID
```

`catalogo-api` y `catalogo-frontend` conservan solo `cap_drop: [ALL]`, sin
`cap_add`.

Verificación del stack completo:

```bash
docker compose up -d
docker compose ps
```

Los tres servicios alcanzan `(healthy)` y la aplicación responde:

```bash
curl -s localhost:3000/api/productos | head -c 200
```

### Por qué la base necesita capabilities y las otras dos capas no

| Servicio | Usuario de ejecución | `cap_drop: [ALL]` | `cap_add` | Motivo |
| --- | --- | --- | --- | --- |
| `catalogo-api` | `appuser` (uid 1000) | Sí | ninguna | Imagen multi-etapa con `USER appuser`: nunca es root, no hace `chown` ni `setuid` |
| `catalogo-frontend` | `nginx` (uid 101) | Sí | ninguna | Imagen `nginx-unprivileged`: nginx arranca sin privilegios de root |
| `catalogo-db` | root → `mongodb` | Sí | CHOWN, FOWNER, DAC_OVERRIDE, SETUID, SETGID | Entrypoint oficial arranca como root, ajusta permisos de `/data/db` en el volumen y luego hace `setuid`/`setgid` al usuario `mongodb` |

Las dos imágenes propias heredan el diseño del Trabajo Práctico Nº 2 (usuario no
privilegiado en el Dockerfile). MongoDB, en cambio, usa el entrypoint de la
imagen oficial: necesita un subconjunto mínimo de capabilities para preparar el
datadir y bajar de root a su usuario de servicio. No se usa `privileged: true`:
se quitan todas las capabilities y se devuelven solo las cinco imprescindibles.

## De tres `docker run` a un `docker-compose.yml` (Trabajo Practico Nº 4 - Ejercicio 12)

En la semana 3 el stack se levantaba con pasos manuales y tres contenedores por
separado. En la semana 4, un único archivo declara la misma arquitectura.

### Semana 3 — lo que había que ejecutar

```bash
# 0. Infraestructura (antes de los contenedores)
docker network create catalogo-net
docker volume create catalogo-db-data

# 1. Base de datos
docker run -d \
  --name catalogo-db \
  --network catalogo-net \
  -e MONGO_INITDB_ROOT_USERNAME=catalogo_user \
  -e MONGO_INITDB_ROOT_PASSWORD=catalogo_pass \
  -v catalogo-db-data:/data/db \
  mongo:7

# 2. API (después de que MongoDB acepte conexiones)
docker run -d \
  --name catalogo-api \
  --network catalogo-net \
  -e DB_HOST=catalogo-db \
  -e DB_PORT=27017 \
  -e DB_NAME=catalogodb \
  -e DB_USER=catalogo_user \
  -e DB_PASSWORD=catalogo_pass \
  -e APP_VERSION=v1 \
  -e ROOT_PATH=/api \
  -e SEED_DEMO=true \
  -p 8000:8000 \
  catalogo-api:v1

# 3. Frontend (después de que exista catalogo-api en la red)
docker run -d \
  --name catalogo-frontend \
  --network catalogo-net \
  -e API_HOST=catalogo-api \
  -e API_PORT=8000 \
  -p 3000:8080 \
  catalogo-frontend:v1
```

Las imágenes propias se construían aparte (`docker build -t catalogo-api:v1
./backend`, idem frontend) antes del `docker run`.

### Semana 4 — un solo comando

```bash
cp .env.example .env   # contrato de variables
docker compose config
docker compose up --build -d
```

### Qué se conserva (misma arquitectura, otro formato)

| Semana 3 (`docker run`) | Semana 4 (`docker-compose.yml`) |
| --- | --- |
| `--name catalogo-*` | `container_name:` |
| `--network catalogo-net` | `networks:` + bloque `networks.catalogo-net.name` |
| `-v catalogo-db-data:/data/db` | `volumes:` + bloque `volumes.catalogo-db-data.name` |
| `-e VAR=valor` | `environment:` con `${VAR}` desde `.env` |
| `-p 3000:8080` / `-p 8000:8000` | `ports:` |
| Sin `-p` en la base | sin `ports` en `catalogo-db` |
| `docker build` + etiqueta | `build:` + `image:` en el mismo servicio |

Red, volumen, nombres de contenedor, variables, puertos y rutas de build son los
mismos; solo cambió la notación declarativa.

### Qué desapareció

| Antes (semana 3) | Por qué ya no hace falta |
| --- | --- |
| `docker network create catalogo-net` | Compose crea la red al hacer `up` (con `name:` explícito) |
| `docker volume create catalogo-db-data` | Compose reutiliza el volumen nombrado al hacer `up` |
| Orden manual red → volumen → db → api → frontend | `depends_on` con `condition: service_healthy` |
| Espera manual a *Waiting for connections* | Healthcheck de `catalogo-db` + dependencia condicionada |
| Recordar el orden en la cabeza de quien levanta | El orden vive en el archivo versionado del repositorio |
| `docker build` como paso separado previo | `docker compose up --build` construye e levanta junto |
| Credenciales en claro en la línea de comando | `.env` (ignorado por git) + `.env.example` documentado |
| Cuatro o más comandos sueltos en la terminal | Un `docker compose up -d` para todo el stack |
| `docker rm -f` / `docker network rm` entre pruebas | `docker compose down` (y `down -v` si se quiere borrar datos) |

### Qué apareció

| Nuevo en Compose | Para qué sirve |
| --- | --- |
| `healthcheck` en los tres servicios | Define cuándo un servicio está realmente listo (`healthy`) |
| `depends_on` + `condition: service_healthy` | Encadena db → api → frontend sin intervención manual |
| Bloques `networks:` y `volumes:` de nivel superior | Mismos nombres que la semana 3, declarados una sola vez |
| `build.context` en api y frontend | Fuente única de verdad para construir imágenes propias |
| `.env` / `.env.example` | Contrato de variables; contraseñas fuera del repositorio |
| `cap_drop: [ALL]` en los tres servicios | Mínimo privilegio a nivel de capabilities |
| `cap_add` en `catalogo-db` | Solo las cinco capabilities que MongoDB necesita para arrancar |
| `docker compose config` | Validar el archivo antes de levantar |
| `docker compose ps` con columna de salud | Ver `(healthy)` / `(unhealthy)` de un vistazo |
| Escaneo Trivy documentado | Revisión de vulnerabilidades de las imágenes propias |

### Resumen

La semana 3 demostró que el stack **funciona**; la semana 4 lo **declara**. Lo
que desaparece es la fricción operativa — comandos sueltos, orden en memoria,
esperas manuales y credenciales en la terminal. Lo que aparece es
orquestación declarativa, salud verificable, dependencias condicionadas,
seguridad básica (`cap_drop`/`cap_add`) y un archivo que en la semana 5 se
traducirá a manifiestos de Kubernetes.

## Imágenes en el clúster e ImagePullBackOff (Trabajo Práctico Nº 5 - Ejercicio 1)

El clúster de Kubernetes corre en otra máquina y no utiliza la caché de
imágenes del Docker Engine local. Las imágenes propias deben publicarse en un
registry y nombrarse de forma completa en los manifiestos.

### Publicación en Docker Hub

Las imágenes ya estaban publicadas desde el Trabajo Práctico Nº 2:

- [diazrodrigoar/catalogo-api:v1](https://hub.docker.com/repository/docker/diazrodrigoar/catalogo-api/tags/v1)
- [diazrodrigoar/catalogo-frontend:v1](https://hub.docker.com/repository/docker/diazrodrigoar/catalogo-frontend/tags/v1)

Comandos equivalentes a los del enunciado:

```bash
docker login
docker tag catalogo-api:v1       diazrodrigoar/catalogo-api:v1
docker tag catalogo-frontend:v1 diazrodrigoar/catalogo-frontend:v1
docker push diazrodrigoar/catalogo-api:v1
docker push diazrodrigoar/catalogo-frontend:v1
```

En los manifiestos de esta entrega se usa el nombre completo
`diazrodrigoar/<imagen>:v1`. Sin el prefijo del usuario, el kubelet busca en
Docker Hub una imagen **oficial** con ese nombre — que no existe.

### Error deliberado: imagen sin usuario del registry

Se creó un Pod de prueba con la imagen mal nombrada:

```bash
kubectl run catalogo-api-pull-test \
  --image=catalogo-api:v1 \
  -n default
```

Salida de `kubectl describe pod catalogo-api-pull-test -n default`:

```
Name:             catalogo-api-pull-test
Namespace:        default
Priority:         0
Service Account:  default
Node:             rdiaz/172.16.20.15
Start Time:       Sun, 18 Oct 2026 22:28:20 -0300
Labels:           run=catalogo-api-pull-test
Annotations:      <none>
Status:           Pending
IP:               10.244.0.7
IPs:
  IP:  10.244.0.7
Containers:
  catalogo-api-pull-test:
    Container ID:
    Image:          catalogo-api:v1
    Image ID:
    Port:           <none>
    Host Port:      <none>
    State:          Waiting
      Reason:       ImagePullBackOff
    Ready:          False
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-bkn7j (ro)
Events:
  Type     Reason     Age                  From               Message
  ----     ------     ----                 ----               -------
  Normal   Scheduled  11m                  default-scheduler  Successfully assigned default/catalogo-api-pull-test to rdiaz
  Normal   Pulling    8m31s (x5 over 11m)  kubelet            spec.containers{catalogo-api-pull-test}: Pulling image "catalogo-api:v1"
  Warning  Failed     8m30s (x5 over 11m)  kubelet            spec.containers{catalogo-api-pull-test}: Failed to pull image "catalogo-api:v1": failed to pull and unpack image "docker.io/library/catalogo-api:v1": failed to resolve reference "docker.io/library/catalogo-api:v1": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     8m30s (x5 over 11m)  kubelet            spec.containers{catalogo-api-pull-test}: Error: ErrImagePull
  Normal   BackOff    86s (x43 over 11m)   kubelet            spec.containers{catalogo-api-pull-test}: Back-off pulling image "catalogo-api:v1"
  Warning  Failed     86s (x43 over 11m)   kubelet            spec.containers{catalogo-api-pull-test}: Error: ImagePullBackOff
```

### Diagnóstico

| Dato | Valor |
| --- | --- |
| Estado del contenedor | `Waiting` → `Reason: ImagePullBackOff` |
| Imagen declarada en el manifiesto | `catalogo-api:v1` |
| Imagen que intentó descargar el kubelet | `catalogo-api:v1` → resuelta como `docker.io/library/catalogo-api:v1` |
| Mensaje clave en Events | `Failed to pull image "catalogo-api:v1"` · `Error: ErrImagePull` · `Error: ImagePullBackOff` |
| Imagen correcta | `diazrodrigoar/catalogo-api:v1` |

El contenedor nunca arrancó: `Container ID` e `Image ID` están vacíos y
`kubectl logs` no devuelve nada. La causa se lee en los **Events** de
`kubectl describe`: el kubelet resolvió `catalogo-api:v1` como imagen oficial
de Docker Hub (`docker.io/library/...`) y no la encontró.

Este error es distinto del `CrashLoopBackOff` de la consigna 5: aquí la imagen
no se descarga; allí la imagen sí baja pero la aplicación falla al ejecutarse
(por ejemplo, porque `DB_HOST=catalogo-db` no resuelve sin un Service).

Limpieza del Pod de prueba:

```bash
kubectl delete pod catalogo-api-pull-test -n default
```
