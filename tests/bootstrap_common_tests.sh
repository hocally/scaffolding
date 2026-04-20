#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=bootstrap/common.sh
. "${REPO_ROOT}/bootstrap/common.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    printf 'bootstrap common test failed: %s\n' "${description}" >&2
    printf 'expected: %s\n' "${expected}" >&2
    printf 'actual: %s\n' "${actual}" >&2
    exit 1
  fi
}

assert_success() {
  local description="$1"
  shift

  if ! "$@"; then
    printf 'bootstrap common test failed: %s\n' "${description}" >&2
    exit 1
  fi
}

assert_failure() {
  local description="$1"
  shift

  if "$@"; then
    printf 'bootstrap common test failed: %s\n' "${description}" >&2
    exit 1
  fi
}

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

cat > "${tmp}" <<'EOF'
GITEA_BOOTSTRAP=1
GITEA_ADMIN_EMAIL=admin@example.invalid
GITEA_ADMIN_PASSWORD=secret
JELLYFIN_BOOTSTRAP=1
JELLYFIN_ADMIN_PASSWORD=secret
EOF

set_env_value "${tmp}" "GITEA_ADMIN_EMAIL" ""
assert_success "GITEA_ADMIN_EMAIL is cleared" grep -qx 'GITEA_ADMIN_EMAIL=' "${tmp}"

set_env_value "${tmp}" "GITEA_ADMIN_PASSWORD" ""
assert_success "GITEA_ADMIN_PASSWORD is cleared" grep -qx 'GITEA_ADMIN_PASSWORD=' "${tmp}"

set_env_value "${tmp}" "GITEA_BOOTSTRAP" "0"
assert_success "GITEA_BOOTSTRAP is disabled" grep -qx 'GITEA_BOOTSTRAP=0' "${tmp}"

set_env_value "${tmp}" "JELLYFIN_ADMIN_PASSWORD" ""
assert_success "JELLYFIN_ADMIN_PASSWORD is cleared" grep -qx 'JELLYFIN_ADMIN_PASSWORD=' "${tmp}"

set_env_value "${tmp}" "JELLYFIN_BOOTSTRAP" "0"
assert_success "JELLYFIN_BOOTSTRAP is disabled" grep -qx 'JELLYFIN_BOOTSTRAP=0' "${tmp}"

assert_equal "/repo/bootstrap/key.pub" "$(resolve_operator_path "/repo" "bootstrap/key.pub")" "relative paths are resolved from the provided base"
assert_equal "/home/operator/.ssh/id.pub" "$(resolve_operator_path "/repo" "/home/operator/.ssh/id.pub")" "absolute paths are preserved"

assert_success "simple repo name is valid" valid_gitea_repo_name "notes"
assert_success "dotted repo name is valid" valid_gitea_repo_name "home.server"
assert_failure "repo name cannot start with dot" valid_gitea_repo_name ".hidden"
assert_failure "repo name cannot end with dot" valid_gitea_repo_name "hidden."
assert_failure "repo name cannot contain path separators" valid_gitea_repo_name "owner/notes"
assert_failure "repo name cannot contain dot-dot" valid_gitea_repo_name "bad..repo"

assert_equal 'quote\"slash\\' "$(json_escape 'quote"slash\')" "JSON strings escape quotes and backslashes"
assert_equal 'Movies%20%26%20TV%2FShows' "$(urlencode 'Movies & TV/Shows')" "URL encoding escapes query separators"
assert_equal 'it%27s%20ok' "$(urlencode "it's ok")" "URL encoding escapes apostrophes and spaces"

printf 'bootstrap common tests: ok\n'
