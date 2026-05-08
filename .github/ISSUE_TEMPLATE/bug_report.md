---
name: Bug report
about: Report a deployment or image behavior problem
title: ''
labels: bug
assignees: ''
---

## Problem

Describe what is failing and what you expected to happen.

## Image

- Image reference:
- Tag:
- Digest:
- Architecture:

## Runtime

- Docker version:
- Docker Compose version:
- Host OS:

## Cloudflare

- DNS-only or proxied:
- DNS-01 is enabled:
- Trusted proxy mode: static CIDRs or dynamic `cloudflare`

## CrowdSec

- Using CrowdSec:
- Using appsec:
- Relevant CrowdSec logs or metrics:

## Compose

Paste the smallest sanitized Compose snippet that reproduces the issue. Redact secrets and private hostnames.

```yaml

```

## Logs

Paste relevant Caddy logs and any related container logs.

```text

```

## Generated Caddy Config

If you can safely extract the generated Caddy config, paste the relevant sanitized block.

```caddyfile

```

## Reproduction

List the exact commands or steps that reproduce the issue.
