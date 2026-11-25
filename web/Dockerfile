# Build stage; the runtime image is nginx and static files only.
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
# Installs exactly the lockfile.
RUN npm ci
COPY . .
RUN npm run build

# Runs as uid 101 on 8080 without config changes.
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
