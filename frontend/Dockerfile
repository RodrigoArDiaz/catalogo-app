# Etapa 1: construir el frontend
FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci

COPY . .

RUN npm run build


# Etapa 2: servir el frontend
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY --from=builder /app/dist/ /usr/share/nginx/html/

EXPOSE 8080