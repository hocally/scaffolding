#!/usr/bin/env bash

script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

repo_root() {
  local dir
  dir="$(script_dir)"
  cd "${dir}/.." && pwd
}

resolve_compose_dir() {
  local root
  root="$(repo_root)"

  if [[ -n "${COMPOSE_DIR:-}" ]]; then
    cd "${COMPOSE_DIR}" && pwd
  elif [[ -f /srv/compose/docker-compose.yml ]]; then
    printf '%s\n' "/srv/compose"
  else
    printf '%s\n' "${root}/compose"
  fi
}

compose_env_file() {
  local compose_dir="$1"

  if [[ -f "${compose_dir}/.env" ]]; then
    printf '%s\n' "${compose_dir}/.env"
  elif [[ -f "${compose_dir}/.env.example" ]]; then
    printf '%s\n' "${compose_dir}/.env.example"
  else
    return 1
  fi
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

docker_info_error_message() {
  local output="$1"

  if printf '%s\n' "${output}" | grep -Eqi 'permission denied.*(docker API|docker\.sock)'; then
    cat <<'EOF'
docker daemon is running, but this shell cannot access the Docker socket.
If bootstrap just added this user to the docker group, log out and back in, or run validation once with:
  sg docker -c 'COMPOSE_DIR=/srv/compose ./scripts/validate.sh'
EOF
    return
  fi

  printf 'docker daemon is not reachable'
  if [[ -n "${output}" ]]; then
    printf '\n%s\n' "${output}"
  else
    printf '\n'
  fi
}
