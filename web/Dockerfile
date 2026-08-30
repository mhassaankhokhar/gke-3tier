# Build the bundle, then throw the toolchain away.
#
# The runtime image carries nginx and static files — no Node, no npm, no
# node_modules. That is much of the reason to serve a SPA this way: both the
# image and the attack surface shrink to almost nothing.
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
# `npm ci` rather than `npm install`: it installs exactly the lockfile, so the
# image cannot quietly differ from what was tested.
RUN npm ci
COPY . .
RUN npm run build

# nginx-unprivileged rather than the standard image. The stock nginx starts as
# root to bind port 80 and to write its pid and temp files into root-owned
# directories; making it run as a normal user means chown-ing several paths and
# rewriting the config. This variant is built for it, listens on 8080, and runs
# as uid 101 with nothing added.
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
