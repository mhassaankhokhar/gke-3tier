FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=build /app/node_modules ./node_modules
COPY . .
USER appuser
EXPOSE 3000
CMD ["node", "./bin/www"]
