# Contributing

This is a solo-maintained utility image. Contributions are welcome when they keep the image practical, focused, and maintainable.

## Pull Requests

Keep PRs small and scoped. A good PR should explain:

- what operational problem it solves
- what changed
- how it was tested
- whether it changes the public deployment contract

CI must pass before merge.

## Module Additions

This image is intentionally opinionated. A module addition should include:

- a link to the upstream module
- the use case it enables
- why it belongs in this image instead of a custom Caddy build
- maintenance and security implications
- how you tested it in Docker Compose

Routine dependency updates are handled by Renovate.

## Documentation

Update `README.md` or `docker-compose.yml` when a change affects how operators deploy, configure, update, or verify the image. Avoid README churn for internal-only CI or maintenance changes.
