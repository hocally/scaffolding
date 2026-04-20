#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
. "${SCRIPT_DIR}/common.sh"

COMPOSE_DIR="$(resolve_compose_dir)"
ENV_FILE="$(compose_env_file "${COMPOSE_DIR}")"

cat <<'NOTES'
Manual upgrade workflow:

1. Read upstream release notes for the service you intend to upgrade.
2. Update the pinned image tag and digest in compose/docker-compose.yml.
3. Run compose config validation.
4. Pull and restart only the affected service.
5. Check logs and smoke-test the service.
6. Commit the changed pin, digest, and any notes.

Commands:
NOTES

cat <<EOF
cd ${COMPOSE_DIR}
docker compose --env-file ${ENV_FILE} config --quiet
docker compose --env-file ${ENV_FILE} pull <service>
docker compose --env-file ${ENV_FILE} up -d <service>
docker compose --env-file ${ENV_FILE} logs --tail 100 <service>
EOF

printf '\nCurrent pinned images:\n'
awk '
  $1 == "image:" {
    print "  " $2
  }
' "${COMPOSE_DIR}/docker-compose.yml"
