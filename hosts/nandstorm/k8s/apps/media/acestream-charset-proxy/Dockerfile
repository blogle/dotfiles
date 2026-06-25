FROM golang:1.22-alpine AS builder
WORKDIR /build
COPY go.mod go.sum main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/proxy .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /out/proxy /proxy
EXPOSE 8889
USER nonroot:nonroot
ENTRYPOINT ["/proxy"]