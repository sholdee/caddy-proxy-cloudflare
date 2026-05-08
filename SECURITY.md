# Security

This image is intended for internet-facing reverse proxy deployments, so security reports are taken seriously.

## Reporting A Vulnerability

Use GitHub private vulnerability reporting or a private security advisory when the report includes exploitable details, secrets, bypass techniques, or other sensitive information.

Use a public issue only for non-sensitive hardening discussion, documentation gaps, or general security questions.

## What To Include

Include enough detail to reproduce or assess the issue:

- affected image tag or digest
- architecture
- relevant Caddy, CrowdSec, or container logs
- sanitized Compose labels
- expected and actual behavior
- whether Cloudflare is proxied or DNS-only for the affected hostname

Do not include live secrets, API tokens, private keys, or unredacted internal hostnames.

## Scope

Useful reports include:

- a vulnerability in this image's build or release process
- unsafe default documentation in this repository
- an issue caused by the bundled Caddy module set
- a meaningful container hardening regression

Reports for Caddy, Cloudflare, CrowdSec, Docker, or a bundled module may need to be reported upstream when the issue is not specific to this image.

## License

This security policy is licensed under the MIT license.
