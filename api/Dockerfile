FROM node:22-alpine
WORKDIR /app

COPY package*.json ./
# No dev dependencies at runtime.
RUN npm ci --omit=dev

COPY . .

# Non-root (the image's built-in node user).
USER node

EXPOSE 3000
CMD ["node", "./bin/www"]
