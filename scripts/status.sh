#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
. "${SCRIPT_DIR}/common.sh"

COMPOSE_DIR="$(resolve_compose_dir)"
ENV_FILE="$(compose_env_file "${COMPOSE_DIR}")"

printf 'compose directory: %s\n\n' "${COMPOSE_DIR}"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --no-pager --full status docker || true
  printf '\n'
fi

(
  cd "${COMPOSE_DIR}"
  docker compose --env-file "${ENV_FILE}" ps
)

printf '\nlistening sockets:\n'
if command -v ss >/dev/null 2>&1; then
  ss -tulpn
else
  netstat -tulpn
fi
