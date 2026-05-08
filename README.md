[![CI](https://github.com/sholdee/caddy-proxy-cloudflare/actions/workflows/main.yml/badge.svg)](https://github.com/sholdee/caddy-proxy-cloudflare/actions/workflows/main.yml)
<a href="Dockerfile"><img src="https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsholdee%2Fcaddy-proxy-cloudflare%2Fmain%2FDockerfile&amp;search=%5EFROM%20golang%3A(%5Cd%2B%5C.%5Cd%2B%5C.%5Cd%2B)-&amp;replace=%241&amp;label=go&amp;color=00ADD8&amp;logo=go" alt="Go Version"></a>
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GHCR image](https://img.shields.io/badge/image-ghcr.io%2Fsholdee%2Fcaddy--proxy--cloudflare-blue)](https://github.com/sholdee/caddy-proxy-cloudflare/pkgs/container/caddy-proxy-cloudflare)

# caddy-proxy-cloudflare

An opinionated Caddy image for Docker Compose homelab edge stacks. It is built for Docker label-driven Caddy config, Cloudflare DNS-01 wildcard certificates, Cloudflare client IP handling, CrowdSec/appsec enforcement, optional Cloudflare Access JWT checks, and a hardened non-root distroless runtime.

This is not a beginner Caddy tutorial. It is meant for operators who already understand Docker Compose, DNS, reverse proxies, and the risk profile of mounting the Docker socket.

## What Is Included

The image is built from the repository `Dockerfile` with:

- Caddy
- `github.com/lucaslorentz/caddy-docker-proxy/v2`
- `github.com/caddy-dns/cloudflare`
- `github.com/WeidiDeng/caddy-cloudflare-ip`
- `github.com/hslatman/caddy-crowdsec-bouncer/http`
- `github.com/hslatman/caddy-crowdsec-bouncer/appsec`
- `github.com/ggicci/caddy-jwt`

The final image runs as `nonroot:nonroot` on a pinned distroless base image and includes a small healthcheck binary.

## Images

GHCR is the primary registry:

```text
ghcr.io/sholdee/caddy-proxy-cloudflare
```

Docker Hub is published as a compatibility fallback:

```text
docker.io/sholdee/caddy-proxy-cloudflare
```

Recommended reference styles:

```text
# Production: pin a date tag and digest.
ghcr.io/sholdee/caddy-proxy-cloudflare:YYYY.MM.DD@sha256:<digest>

# Normal updates: use the date tag.
ghcr.io/sholdee/caddy-proxy-cloudflare:YYYY.MM.DD

# Quick tests only.
ghcr.io/sholdee/caddy-proxy-cloudflare:latest
```

## Compose Pattern

The canonical example is [`docker-compose.yml`](docker-compose.yml). It uses a small edge stack:

- `caddy`: the socket-reading Caddy runtime
- `caddy-config`: a no-op label carrier for global Caddy config
- `crowdsec`: optional CrowdSec local API and appsec service
- `whoami`: a tiny demo upstream

The `caddy-config` container is intentional. It lets `caddy-docker-proxy` watch label changes and hot-reload generated Caddy config without recreating the actual Caddy runtime container. In practice, this keeps the edge proxy stable while still making label-driven config edits cheap.

The example pins the `2026.05.08` release by digest. Replace that image reference when you intentionally update to a newer release.

Create a local `.env` for the example:

```env
DOMAIN=example.com
EMAIL_ADDR=admin@example.com
CF_TOKEN=replace-with-cloudflare-api-token
CROWDSEC_API_KEY=replace-with-shared-bouncer-key
DOCKER_GID=123
TZ=America/Chicago
```

Set `DOCKER_GID` to the group ID that owns `/var/run/docker.sock` on the host:

```bash
getent group docker
```

The example exposes HTTP, HTTPS, and HTTP/3:

```yaml
ports:
  - "80:80/tcp"
  - "443:443/tcp"
  - "443:443/udp"
```

## Cloudflare

The example uses Cloudflare DNS-01 validation:

```yaml
labels:
  caddy.acme_dns: "cloudflare ${CF_TOKEN}"
```

Use a scoped Cloudflare API token that can edit DNS records for the zone. The Cloudflare DNS module documents the token requirements in [`libdns/cloudflare`](https://github.com/libdns/cloudflare#authenticating).

The canonical compose file uses a static Cloudflare proxy CIDR list:

```yaml
caddy.servers.trusted_proxies: "static 173.245.48.0/20 ..."
caddy.servers.client_ip_headers: "Cf-Connecting-Ip"
```

Static CIDRs make the edge behavior predictable. The bundled Cloudflare IP module also supports dynamic Cloudflare proxy discovery with `caddy.servers.trusted_proxies: "cloudflare"` if you prefer runtime refreshes.

## CrowdSec

CrowdSec is first-class in the example, but optional. If you do not use CrowdSec, remove:

- the `crowdsec` service
- `caddy.crowdsec.*` labels from `caddy-config`
- `crowdsec` and `appsec` route labels from upstream services
- the `acquis.yaml` mount

The example keeps the CrowdSec streaming bouncer enabled and sets:

```yaml
environment:
  - CADDY_DOCKER_EVENT_THROTTLE_INTERVAL=3s
```

That throttle prevents rapid Docker event bursts from causing repeated graceful reloads. In this stack, it is the practical workaround for reload bursts interacting poorly with the streaming bouncer/admin API path. If your environment still sees reload timeouts, increase the throttle or test the bouncer's polling mode.

[`acquis.yaml`](acquis.yaml) is the minimal CrowdSec Docker acquisition file used by the example. It tells CrowdSec to read Caddy logs from the Docker socket and classify them as Caddy logs.

## Advanced Patterns

### Cloudflare Access JWT

The image includes `caddy-jwt`, so a route can require Cloudflare Access JWTs. Keep this out of the global default unless every service behind that route should require Access.

```yaml
labels:
  caddy: "app.${DOMAIN}"
  caddy.@remote.not: "remote_ip 192.168.0.0/16 10.0.0.0/8"
  caddy.route.1_jwtauth: "@remote"
  caddy.route.1_jwtauth.jwk_url: "https://<team-name>.cloudflareaccess.com/cdn-cgi/access/certs"
  caddy.route.1_jwtauth.from_header: "Cf-Access-Jwt-Assertion"
  caddy.route.1_jwtauth.from_cookies: "CF_Authorization"
  caddy.route.1_jwtauth.issuer_whitelist: "https://<team-name>.cloudflareaccess.com"
  caddy.route.1_jwtauth.audience_whitelist: "<cloudflare-access-audience-id>"
  caddy.route.2_reverse_proxy: "{{upstreams 8080}}"
```

### Small Reusable Snippet

Caddy Docker Proxy labels can define named snippets and import them into routes. This is useful for repeated headers or upstream defaults.

```yaml
labels:
  caddy_0: "(upstream_defaults)"
  caddy_0.header: "-Server"
  caddy_0.encode: "zstd gzip"

  caddy: "app.${DOMAIN}"
  caddy.import: "upstream_defaults"
  caddy.reverse_proxy: "{{upstreams 8080}}"
```

## Operator Checks

Validate and start the example:

```bash
docker compose config
docker compose up -d
```

Check Caddy and CrowdSec:

```bash
docker logs caddy --tail=100
docker exec crowdsec cscli metrics
curl -I https://whoami.example.com
```

If Caddy is not issuing certificates, check the Cloudflare token scope, DNS zone, and `caddy.acme_dns` label first.

## Updating Digests

Resolve the digest for a date tag:

```bash
docker buildx imagetools inspect ghcr.io/sholdee/caddy-proxy-cloudflare:YYYY.MM.DD
```

Copy the top-level manifest digest into Compose:

```yaml
image: ghcr.io/sholdee/caddy-proxy-cloudflare:YYYY.MM.DD@sha256:<digest>
```

If you run Renovate against your Compose repository, it can also maintain digest-pinned image references.

## Supply Chain

Release images are signed with keyless `cosign`. Production deployments should prefer digest-pinned references and can verify a published digest:

```bash
cosign verify ghcr.io/sholdee/caddy-proxy-cloudflare@sha256:<digest> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity https://github.com/sholdee/caddy-proxy-cloudflare/.github/workflows/main.yml@refs/heads/main
```

The release workflow also verifies the distroless runtime base image before publishing.

## Boundaries

This repository is intentionally narrow:

- It is not a general Caddy module marketplace.
- It is not a replacement for learning Caddy, Cloudflare, Docker, or CrowdSec.
- It is not a complete homelab security model.
- It does not remove the risk of Docker socket access. The socket is mounted read-only, but Docker API read access is still powerful. Keep the Caddy runtime otherwise locked down and only run this pattern on hosts where that tradeoff is acceptable.

## License

MIT. See [`LICENSE`](LICENSE).
