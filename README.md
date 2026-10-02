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