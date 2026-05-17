FROM --platform=$BUILDPLATFORM golang:1.26.3-trixie@sha256:a085df697019cb63b40a70f6a92b948f7dc9df96dfcb2c20ba6eed25ce28f5b3 AS gobuild

ARG TARGETOS
ARG TARGETARCH

WORKDIR /go/src/github.com/caddyserver/xcaddy/cmd/xcaddy

RUN apt update && apt install -y git gcc build-essential && \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.6

ENV CGO_ENABLED=0
ENV CADDY_VERSION=v2.11.3

RUN GOOS=$TARGETOS GOARCH=$TARGETARCH xcaddy build \
    --output /go/src/github.com/caddyserver/xcaddy/cmd/caddy \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@v2.12.0 \
    --with github.com/caddy-dns/cloudflare@v0.2.4 \
    --with github.com/WeidiDeng/caddy-cloudflare-ip@v0.0.0-20231130002422-f53b62aa13cb \
    --with github.com/mholt/caddy-l4@v0.1.1 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v0.12.1 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/appsec@v0.12.1 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/layer4@v0.12.1 \
    --with github.com/ggicci/caddy-jwt@v1.2.0 \
    --with github.com/zhangjiayin/caddy-geoip2@v0.0.0-20251231005803-9e40d38250b4

WORKDIR /go/src/healthcheck
COPY healthcheck*.go .
RUN go test healthcheck.go healthcheck_test.go && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /healthcheck -ldflags="-s -w" healthcheck.go

FROM scratch AS binary-export
ARG TARGETOS
ARG TARGETARCH
COPY --from=gobuild /go/src/github.com/caddyserver/xcaddy/cmd/caddy /caddy-proxy-cloudflare-${TARGETOS}-${TARGETARCH}

FROM gcr.io/distroless/static-debian13:nonroot@sha256:963fa6c544fe5ce420f1f54fb88b6fb01479f054c8056d0f74cc2c6000df5240
EXPOSE 80 443 2019

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

COPY --from=gobuild /go/src/github.com/caddyserver/xcaddy/cmd/caddy /bin/
COPY --from=gobuild /healthcheck /bin/

USER nonroot:nonroot

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s CMD ["/bin/healthcheck"]

ENTRYPOINT ["/bin/caddy"]

CMD ["docker-proxy"]
