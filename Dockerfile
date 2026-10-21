FROM --platform=$BUILDPLATFORM golang:1.27.3-trixie@sha256:290a54a1f70d617560f843301bcb32b339f1687e8e0bff49ebc043903aeb19d8 AS gobuild

ARG TARGETOS
ARG TARGETARCH

WORKDIR /go/src/github.com/caddyserver/xcaddy/cmd/xcaddy

RUN apt update && apt install -y git gcc build-essential && \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.7

ENV CGO_ENABLED=0
ENV CADDY_VERSION=v2.11.7

RUN GOOS=$TARGETOS GOARCH=$TARGETARCH xcaddy build \
    --output /go/src/github.com/caddyserver/xcaddy/cmd/caddy \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@v2.13.1 \
    --with github.com/caddy-dns/cloudflare@v0.2.4 \
    --with github.com/WeidiDeng/caddy-cloudflare-ip@v0.0.0-20231130002422-f53b62aa13cb \
    --with github.com/mholt/caddy-l4@v0.1.2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v0.14.1 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/appsec@v0.14.1 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/layer4@v0.14.1 \
    --with github.com/ggicci/caddy-jwt@v1.4.0 \
    --with github.com/zhangjiayin/caddy-geoip2@v1.3.1

WORKDIR /go/src/healthcheck
COPY healthcheck*.go .
RUN go test healthcheck.go healthcheck_test.go && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /healthcheck -ldflags="-s -w" healthcheck.go

FROM scratch AS binary-export
ARG TARGETOS
ARG TARGETARCH
COPY --from=gobuild /go/src/github.com/caddyserver/xcaddy/cmd/caddy /caddy-proxy-cloudflare-${TARGETOS}-${TARGETARCH}

FROM gcr.io/distroless/static-debian13:nonroot@sha256:516757106de35205efb70b91ba03f6f1298424a0678c603255cf2852a7000087
EXPOSE 80 443 2019

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

COPY --from=gobuild /go/src/github.com/caddyserver/xcaddy/cmd/caddy /bin/
COPY --from=gobuild /healthcheck /bin/

USER nonroot:nonroot

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s CMD ["/bin/healthcheck"]

ENTRYPOINT ["/bin/caddy"]

CMD ["docker-proxy"]
