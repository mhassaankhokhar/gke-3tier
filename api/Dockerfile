FROM node:22-alpine
WORKDIR /app

COPY package*.json ./
# --omit=dev because the runtime needs none of the build tooling, and every
# package that is not installed is one that cannot carry a vulnerability.
RUN npm ci --omit=dev

COPY . .

# A normal user, created rather than assumed. node:alpine ships a `node` user
# for exactly this, and running as root inside a container means a container
# escape starts with root rather than having to find it.
USER node

EXPOSE 3000
CMD ["node", "./bin/www"]
