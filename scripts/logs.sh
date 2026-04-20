#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
. "${SCRIPT_DIR}/common.sh"

COMPOSE_DIR="$(resolve_compose_dir)"
ENV_FILE="$(compose_env_file "${COMPOSE_DIR}")"
TAIL="${TAIL:-100}"

(
  cd "${COMPOSE_DIR}"
  docker compose --env-file "${ENV_FILE}" logs --tail "${TAIL}" -f "$@"
)
