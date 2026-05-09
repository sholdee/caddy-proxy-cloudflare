[![CI](https://github.com/sholdee/caddy-proxy-cloudflare/actions/workflows/main.yml/badge.svg)](https://github.com/sholdee/caddy-proxy-cloudflare/actions/workflows/main.yml)
<a href="Dockerfile"><img src="https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsholdee%2Fcaddy-proxy-cloudflare%2Fmain%2FDockerfile&amp;search=%5EFROM%28%3F%3A%20--platform%3D%5C%24BUILDPLATFORM%29%3F%20golang%3A(%5Cd%2B%5C.%5Cd%2B%5C.%5Cd%2B)-&amp;replace=%241&amp;label=go&amp;color=00ADD8&amp;logo=go" alt="Go Version"></a>
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GHCR image](https://img.shields.io/badge/image-ghcr.io%2Fsholdee%2Fcaddy--proxy--cloudflare-blue)](https://github.com/sholdee/caddy-proxy-cloudflare/pkgs/container/caddy-proxy-cloudflare)

# caddy-proxy-cloudflare

An opinionated Caddy image for Docker Compose homelab edge stacks. It is built for Docker label-driven Caddy config, Cloudflare DNS-01 wildcard certificates, Cloudflare client IP handling, CrowdSec/appsec enforcement, optional Cloudflare Access JWT checks, and a hardened non-root distroless runtime.

This repository assumes working familiarity with Docker Compose, DNS, reverse proxies, and the Docker socket security tradeoff. It is written for operators who want a practical edge-stack pattern rather than a beginner Caddy tutorial.

## What Is Included

The image is built from the repository `Dockerfile` with:

- Caddy
- `github.com/lucaslorentz/caddy-docker-proxy/v2`
- `github.com/caddy-dns/cloudflare`
- `github.com/WeidiDeng/caddy-cloudflare-ip`
- `github.com/hslatman/caddy-crowdsec-bouncer/http`
- `github.com/hslatman/caddy-crowdsec-bouncer/appsec`
- `github.com/ggicci/caddy-jwt`
- `github.com/zhangjiayin/caddy-geoip2`

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
# Production: pin a release tag and digest.
ghcr.io/sholdee/caddy-proxy-cloudflare:vYYYY.MDD.HMMSS@sha256:<digest>

# Normal updates: use the release tag.
ghcr.io/sholdee/caddy-proxy-cloudflare:vYYYY.MDD.HMMSS

# Quick tests only.
ghcr.io/sholdee/caddy-proxy-cloudflare:latest
```

## Host Binary Install

Docker is the primary deployment target, but releases also include Linux `amd64` and `arm64` Caddy binaries for host installs.

Download the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/sholdee/caddy-proxy-cloudflare/main/scripts/install-caddy-proxy-cloudflare.sh \
  -o install-caddy-proxy-cloudflare.sh
chmod +x install-caddy-proxy-cloudflare.sh
```

Install or update to the latest release:

```bash
./install-caddy-proxy-cloudflare.sh
```

The script detects the host architecture, verifies the binary checksum, optionally verifies the checksum Sigstore bundle with `cosign`, summarizes the planned changes, backs up the existing `caddy` binary when present, and restarts an active `caddy.service`.

Useful options:

```bash
./install-caddy-proxy-cloudflare.sh --version vYYYY.MDD.HMMSS
./install-caddy-proxy-cloudflare.sh --yes
./install-caddy-proxy-cloudflare.sh --require-cosign
./install-caddy-proxy-cloudflare.sh list-backups
./install-caddy-proxy-cloudflare.sh restore
```

For systemd hosts without an existing Caddy service, `--install-service` creates a Caddyfile-based `caddy.service` following Caddy's [Linux service guidance](https://caddyserver.com/docs/running#linux-service). It does not overwrite an existing service unless `--force-service` is also set.

## Compose Pattern

The canonical example is [`docker-compose.yml`](docker-compose.yml). It uses a small edge stack:

- `caddy`: the Docker-label Caddy runtime
- `caddy-config`: a no-op label carrier for global Caddy config
- `crowdsec`: optional CrowdSec local API and appsec service
- `whoami`: a tiny demo upstream
- `docker-socket-proxy`: a narrow Docker API proxy for Caddy and CrowdSec

The `caddy-config` container is intentional. It lets `caddy-docker-proxy` watch label changes and hot-reload generated Caddy config without recreating the actual Caddy runtime container. In practice, this keeps the edge proxy stable while still making label-driven config edits cheap.

Keeping reverse-proxy configuration in Compose labels also makes the edge config GitOps-friendly: route changes can move through the same reviewed Compose workflow as the services they expose.

The example does not mount the raw Docker socket into `caddy` or `crowdsec`. Those containers use `DOCKER_HOST=tcp://docker-socket-proxy:2375`, and only `docker-socket-proxy` mounts `/var/run/docker.sock`.

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

The socket group is only added to `docker-socket-proxy`; Caddy and CrowdSec do not receive the raw socket mount.

The example exposes HTTP, HTTPS, and HTTP/3:

```yaml
ports:
  - "80:80/tcp"
  - "443:443/tcp"
  - "443:443/udp"
```

## Docker Socket Proxy

The example uses [`tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy) as a blast-radius reduction layer between the edge stack and Docker. It keeps the raw Docker socket out of Caddy and CrowdSec while still allowing the Docker reads they need for label discovery, event watching, network discovery, and Docker log acquisition.

The proxy is attached only to the internal `edge` network and has no host port mapping. Its Docker API surface is intentionally narrow:

```yaml
environment:
  - CONTAINERS=1
  - EVENTS=1
  - INFO=1
  - NETWORKS=1
  - PING=1
  - VERSION=1
  - POST=0
```

This allows required read paths such as container list/inspect/logs, Docker events, Docker info/version, and network reads. It blocks mutating Docker API calls and leaves broad sections such as images, volumes, exec, services, tasks, swarm, secrets, build, and auth disabled.

Treat socket proxy image updates as manual-review changes. The repository Renovate config detects the image but excludes it from automerge because restarting or changing the proxy can interrupt Docker API access for running Caddy and CrowdSec containers.

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

[`acquis.yaml`](acquis.yaml) is the minimal CrowdSec Docker acquisition file used by the example. It tells CrowdSec to read Caddy logs through `docker-socket-proxy` and classify them as Caddy logs.

## Advanced Patterns

### Cloudflare Access JWT

The image includes `caddy-jwt`, so a route can require Cloudflare Access JWTs. Keep this out of the global default unless every service behind that route should require Access.

The snippet below applies JWT auth only when the client IP is outside the listed internal LAN CIDRs. That pattern is useful for split-DNS deployments where local clients can reach the service directly while remote clients must pass through Cloudflare Access.

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

Resolve the digest for a release tag:

```bash
docker buildx imagetools inspect ghcr.io/sholdee/caddy-proxy-cloudflare:vYYYY.MDD.HMMSS
```

Copy the top-level manifest digest into Compose:

```yaml
image: ghcr.io/sholdee/caddy-proxy-cloudflare:vYYYY.MDD.HMMSS@sha256:<digest>
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
- It does not make Docker metadata harmless. Caddy and CrowdSec no longer receive the raw socket, but the socket proxy still exposes selected Docker read APIs. Keep labels, logs, and container metadata free of secrets, and run this pattern only on hosts where that tradeoff is acceptable.

## License

[`MIT`](LICENSE)
