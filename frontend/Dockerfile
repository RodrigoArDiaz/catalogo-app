# Etapa 1: construir el frontend
FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci

COPY . .

RUN npm run build


# Etapa 2: servir el frontend
FROM nginxinc/nginx-unprivileged:1.27-alpine

ENV API_HOST=catalogo-api \
    API_PORT=8000 \
    NGINX_ENVSUBST_FILTER=^API_

COPY --from=builder /app/dist/ /usr/share/nginx/html/

COPY nginx/templates/default.conf.template \
    /etc/nginx/templates/default.conf.template

EXPOSE 8080