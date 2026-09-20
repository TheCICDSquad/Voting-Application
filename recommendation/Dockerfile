# --- Build stage -------------------------------------------------------
FROM golang:1.20-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /recommendation .

# --- Runtime stage -------------------------------------------------------
FROM alpine:3.19
WORKDIR /app

RUN addgroup -S craftista && adduser -S craftista -G craftista

COPY --from=builder /recommendation .
COPY --from=builder /app/config.json .
COPY --from=builder /app/templates ./templates
COPY --from=builder /app/static ./static

EXPOSE 8080
USER craftista

CMD ["./recommendation"]
