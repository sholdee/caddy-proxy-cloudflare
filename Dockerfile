ARG GOLANG_VERSION=1.23.3
ARG ALPINE_VERSION=3.20

FROM golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} as gobuild

WORKDIR /go/src/github.com/caddyserver/xcaddy/cmd/xcaddy

RUN apk add --no-cache git gcc build-base && \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

ENV CGO_ENABLED=0
RUN xcaddy build \
    --output /go/src/github.com/caddyserver/xcaddy/cmd/caddy \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2 \
    --with github.com/caddy-dns/cloudflare

WORKDIR /go/src/healthcheck
COPY healthcheck.go .
RUN go build -o /healthcheck -ldflags="-s -w" healthcheck.go

FROM gcr.io/distroless/static-debian12:nonroot
EXPOSE 80 443 2019

ENV XDG_CONFIG_HOME /config
ENV XDG_DATA_HOME /data

COPY --from=gobuild /go/src/github.com/caddyserver/xcaddy/cmd/caddy /bin/
COPY --from=gobuild /healthcheck /bin/

USER nonroot:nonroot

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s CMD ["/bin/healthcheck"]

ENTRYPOINT ["/bin/caddy"]

CMD ["docker-proxy"]
