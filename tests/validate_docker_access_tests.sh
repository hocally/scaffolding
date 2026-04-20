#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/common.sh
. "${REPO_ROOT}/scripts/common.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    printf 'validate docker access test failed: %s\n' "${description}" >&2
    printf 'expected to find: %s\n' "${needle}" >&2
    printf 'actual:\n%s\n' "${haystack}" >&2
    exit 1
  fi
}

message="$(
  docker_info_error_message 'permission denied while trying to connect to the docker API at unix:///var/run/docker.sock'
)"
assert_contains "${message}" "cannot access the Docker socket" "permission denied gets a socket-access explanation"
assert_contains "${message}" "sg docker -c" "permission denied suggests the first-login workaround"

message="$(docker_info_error_message 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?')"
assert_contains "${message}" "docker daemon is not reachable" "non-permission failures keep daemon diagnostic"
assert_contains "${message}" "Cannot connect to the Docker daemon" "docker info output is retained"

printf 'validate docker access tests: ok\n'
