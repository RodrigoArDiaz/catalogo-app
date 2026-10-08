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