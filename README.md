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
