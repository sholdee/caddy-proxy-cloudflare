#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: smoke-binary.sh <dist-dir>

Validates release binary artifacts for caddy-proxy-cloudflare.
EOF
}

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

dist_dir="$1"
project="caddy-proxy-cloudflare"
amd64_binary="${project}-linux-amd64"
arm64_binary="${project}-linux-arm64"
checksum_file="checksums-sha256.txt"

required_modules=(
  "docker_proxy"
  "dns.providers.cloudflare"
  "http.ip_sources.cloudflare"
  "crowdsec"
  "http.handlers.crowdsec"
  "http.handlers.appsec"
  "http.authentication.providers.jwt"
  "geoip2"
  "http.handlers.geoip2"
  "layer4"
  "layer4.matchers.crowdsec"
)

need_cmd grep
need_cmd mktemp
need_cmd sha256sum
need_cmd uname

[[ -d "${dist_dir}" ]] || fail "dist directory does not exist: ${dist_dir}"

cd "${dist_dir}"

for binary in "${amd64_binary}" "${arm64_binary}"; do
  [[ -f "${binary}" ]] || fail "missing binary: ${binary}"
  [[ -x "${binary}" ]] || fail "binary is not executable: ${binary}"
done

[[ -f "${checksum_file}" ]] || fail "missing checksum manifest: ${checksum_file}"

for binary in "${amd64_binary}" "${arm64_binary}"; do
  grep -Fq "  ${binary}" "${checksum_file}" || fail "checksum manifest does not include ${binary}"
done

sha256sum --check "${checksum_file}"

case "$(uname -s)" in
  Linux) host_os="linux" ;;
  *) host_os="$(uname -s)" ;;
esac

case "$(uname -m)" in
  x86_64 | amd64) host_arch="amd64" ;;
  aarch64 | arm64) host_arch="arm64" ;;
  *) host_arch="$(uname -m)" ;;
esac

if [[ "${host_os}/${host_arch}" != "linux/amd64" ]]; then
  if [[ "${CADDY_PROXY_SMOKE_REQUIRE_EXEC:-0}" == "1" ]]; then
    fail "executable smoke requires linux/amd64, got ${host_os}/${host_arch}"
  fi

  printf "Skipping executable smoke on %s/%s; linux/amd64 required\n" "${host_os}" "${host_arch}"
  exit 0
fi

printf "Running %s version\n" "${amd64_binary}"
"./${amd64_binary}" version

modules_file="$(mktemp)"
tmpdir="$(mktemp -d)"
trap 'rm -f "${modules_file}"; rm -rf "${tmpdir}"' EXIT

printf "Checking required Caddy modules\n"
"./${amd64_binary}" list-modules > "${modules_file}"
for module in "${required_modules[@]}"; do
  grep -Fxq "${module}" "${modules_file}" || fail "missing Caddy module: ${module}"
done

cat > "${tmpdir}/Caddyfile" <<'EOF'
{
	auto_https off
}

:0 {
	respond "ok"
}
EOF

printf "Validating minimal Caddyfile\n"
"./${amd64_binary}" validate --config "${tmpdir}/Caddyfile"

printf "Binary smoke passed\n"
