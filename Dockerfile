FROM --platform=$BUILDPLATFORM golang:1.26.5-trixie@sha256:4ee9ffa999b4583ce281939cdff828763083610292f252279a0cee77473bd9a7 AS gobuild

ARG TARGETOS
ARG TARGETARCH

WORKDIR /go/src/github.com/caddyserver/xcaddy/cmd/xcaddy

RUN apt update && apt install -y git gcc build-essential && \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.6

ENV CGO_ENABLED=0
ENV CADDY_VERSION=v2.11.4

RUN GOOS=$TARGETOS GOARCH=$TARGETARCH xcaddy build \
    --output /go/src/github.com/caddyserver/xcaddy/cmd/caddy \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@v2.13.1 \
    --with github.com/caddy-dns/cloudflare@v0.2.4 \
    --with github.com/WeidiDeng/caddy-cloudflare-ip@v0.0.0-20231130002422-f53b62aa13cb \
    --with github.com/mholt/caddy-l4@v0.1.2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v0.13.1 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/appsec@v0.13.1 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/layer4@v0.13.1 \
    --with github.com/ggicci/caddy-jwt@v1.3.0 \
    --with github.com/zhangjiayin/caddy-geoip2@v0.0.0-20260623062220-3675c6e7e63d

WORKDIR /go/src/healthcheck
COPY healthcheck*.go .
RUN go test healthcheck.go healthcheck_test.go && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /healthcheck -ldflags="-s -w" healthcheck.go

FROM scratch AS binary-export
ARG TARGETOS
ARG TARGETARCH
COPY --from=gobuild /go/src/github.com/caddyserver/xcaddy/cmd/caddy /caddy-proxy-cloudflare-${TARGETOS}-${TARGETARCH}

FROM gcr.io/distroless/static-debian13:nonroot@sha256:f7f8f729987ad0fdf6b05eeeae94b26e6a0f613bdf46feea7fc40f7bd72953e6
EXPOSE 80 443 2019

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

COPY --from=gobuild /go/src/github.com/caddyserver/xcaddy/cmd/caddy /bin/
COPY --from=gobuild /healthcheck /bin/

USER nonroot:nonroot

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s CMD ["/bin/healthcheck"]

ENTRYPOINT ["/bin/caddy"]

CMD ["docker-proxy"]
