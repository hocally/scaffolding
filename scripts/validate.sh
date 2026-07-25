#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
. "${SCRIPT_DIR}/common.sh"

COMPOSE_DIR="$(resolve_compose_dir)"
ENV_FILE="$(compose_env_file "${COMPOSE_DIR}")"
OFFLINE="${OFFLINE:-0}"
STRICT_DNS="${STRICT_DNS:-0}"

printf 'validating compose directory: %s\n' "${COMPOSE_DIR}"
printf 'using env file: %s\n' "${ENV_FILE}"

[[ -f "${COMPOSE_DIR}/docker-compose.yml" ]] || die "missing docker-compose.yml in ${COMPOSE_DIR}"
[[ -f "${COMPOSE_DIR}/caddy/Caddyfile" ]] || die "missing caddy/Caddyfile in ${COMPOSE_DIR}"

if awk '
  $1 == "image:" && $2 ~ /:latest$/ {
    print "floating latest image tag: " $2
    bad = 1
  }
  $1 == "image:" && $2 !~ /^local\// && $2 !~ /@sha256:[a-f0-9]{64}$/ {
    print "external image missing digest pin: " $2
    bad = 1
  }
  END { exit bad }
' "${COMPOSE_DIR}/docker-compose.yml"; then
  printf 'image pins: ok\n'
else
  die "image pin validation failed"
fi

if [[ "${OFFLINE}" == "1" ]]; then
  printf 'OFFLINE=1; skipped docker daemon and HTTP smoke tests\n'
  printf 'validation complete\n'
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  die "docker is not installed or not in PATH"
fi

docker compose version >/dev/null || die "docker compose plugin is not available"

(
  cd "${COMPOSE_DIR}"
  docker compose --env-file "${ENV_FILE}" config --quiet
)

printf 'compose config: ok\n'

docker_info_output=""
if ! docker_info_output="$(docker info 2>&1 >/dev/null)"; then
  die "$(docker_info_error_message "${docker_info_output}")"
fi

(
  cd "${COMPOSE_DIR}"
  docker compose --env-file "${ENV_FILE}" ps
)

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
fi

GITEA_DOMAIN="${GITEA_DOMAIN:-gitea}"
SAMPLE_DOMAIN="${SAMPLE_DOMAIN:-campsites}"
RETRO_WAVEFORM_DOMAIN="${RETRO_WAVEFORM_DOMAIN:-retro-waveform}"

check_dns_name() {
  local name="$1"

  if command -v getent >/dev/null 2>&1; then
    getent hosts "${name}" >/dev/null 2>&1
    return
  fi

  if command -v dscacheutil >/dev/null 2>&1; then
    [[ -n "$(dscacheutil -q host -a name "${name}" 2>/dev/null)" ]]
    return
  fi

  return 2
}

check_dns_or_report() {
  local name="$1"

  if check_dns_name "${name}"; then
    printf 'dns %s: ok\n' "${name}"
    return 0
  fi

  if [[ "${STRICT_DNS}" == "1" ]]; then
    die "DNS name '${name}' does not resolve. Add a router/local-DNS record pointing ${name} to the server IP, then rerun validation."
  fi

  warn "DNS name '${name}' does not resolve yet; add a router/local-DNS record pointing it to the server IP"
}

check_dns_or_report "${GITEA_DOMAIN}"
check_dns_or_report "${SAMPLE_DOMAIN}"
check_dns_or_report "${RETRO_WAVEFORM_DOMAIN}"

curl_retry() {
  local description="$1"
  shift
  local attempt

  for attempt in 1 2 3 4 5; do
    if curl -fsS --max-time 5 "$@" >/dev/null; then
      printf '%s: ok\n' "${description}"
      return 0
    fi
    sleep 3
  done

  die "${description} failed after retries. Check service status and logs with: COMPOSE_DIR=${COMPOSE_DIR} ${SCRIPT_DIR}/status.sh"
}

if docker ps --format '{{.Names}}' | grep -qx caddy; then
  curl_retry "sample app route http://${SAMPLE_DOMAIN}" -H "Host: ${SAMPLE_DOMAIN}" http://127.0.0.1/
  curl_retry "gitea route http://${GITEA_DOMAIN}" -H "Host: ${GITEA_DOMAIN}" http://127.0.0.1/
  curl_retry "gitea IP/default route" http://127.0.0.1/
  curl_retry "sample app fallback path /campsites" http://127.0.0.1/campsites

  if check_dns_name "${SAMPLE_DOMAIN}"; then
    curl_retry "sample app DNS route http://${SAMPLE_DOMAIN}/healthz" "http://${SAMPLE_DOMAIN}/healthz"
  fi
else
  printf 'caddy is not running; skipped HTTP smoke tests\n'
fi

if docker ps --format '{{.Names}}' | grep -qx jellyfin; then
  curl_retry "jellyfin public system info endpoint" http://127.0.0.1:8096/System/Info/Public
else
  printf 'jellyfin is not running; skipped Jellyfin smoke test\n'
fi

if docker ps --format '{{.Names}}' | grep -qx retro-waveform; then
  curl_retry "retro waveform route http://${RETRO_WAVEFORM_DOMAIN}" -H "Host: ${RETRO_WAVEFORM_DOMAIN}" http://127.0.0.1/api/v1/health/ready
else
  printf 'retro-waveform is not running; skipped Retro Waveform HTTP smoke test\n'
fi

printf 'validation complete\n'
