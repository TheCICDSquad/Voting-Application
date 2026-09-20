# --- Build stage -------------------------------------------------------
FROM node:18-alpine AS builder
WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY . .

# --- Runtime stage -------------------------------------------------------
FROM node:18-alpine
WORKDIR /app

RUN addgroup -S craftista && adduser -S craftista -G craftista

COPY --from=builder /app /app

ENV NODE_ENV=production \
    PORT=3000

EXPOSE 3000
USER craftista

CMD ["node", "app.js"]
