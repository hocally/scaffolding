#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${REPO_ROOT}"

bash -n bootstrap/bootstrap.sh bootstrap/common.sh scripts/*.sh tests/*.sh

for script in \
  bootstrap/bootstrap.sh \
  scripts/logs.sh \
  scripts/network-info.sh \
  scripts/status.sh \
  scripts/upgrade_notes.sh \
  scripts/validate.sh \
  tests/bootstrap_common_tests.sh \
  tests/jellyfin_bootstrap_api_tests.sh \
  tests/network_info_tests.sh \
  tests/public_sanitization_tests.sh \
  tests/validate_docker_access_tests.sh \
  tests/static_repo_checks.sh; do
  if [[ ! -x "${script}" ]]; then
    printf 'script is not executable: %s\n' "${script}" >&2
    exit 1
  fi
done

./tests/bootstrap_common_tests.sh >/dev/null
./tests/network_info_tests.sh >/dev/null
./tests/public_sanitization_tests.sh >/dev/null
./tests/validate_docker_access_tests.sh >/dev/null

OFFLINE=1 COMPOSE_DIR=compose ./scripts/validate.sh >/dev/null

for service in caddy gitea jellyfin sample-app; do
  grep -q "^  ${service}:" compose/docker-compose.yml || {
    printf 'missing service: %s\n' "${service}" >&2
    exit 1
  }
done

restart_count="$(grep -c 'restart: unless-stopped' compose/docker-compose.yml)"
if [[ "${restart_count}" -lt 4 ]]; then
  printf 'expected restart policy on all services; found %s\n' "${restart_count}" >&2
  exit 1
fi

awk '
  $1 == "image:" && $2 ~ /:latest$/ { print "floating compose image: " $2; bad = 1 }
  $1 == "image:" && $2 !~ /^local\// && $2 !~ /@sha256:[a-f0-9]{64}$/ {
    print "external compose image missing digest pin: " $2
    bad = 1
  }
  END { exit bad }
' compose/docker-compose.yml

grep -q 'context: ./apps/sample-app' compose/docker-compose.yml
grep -q 'image: local/campsites-sample:0.1.0' compose/docker-compose.yml

awk '
  /^[[:space:]]+- \// {
    source = $2
    sub(/:.*/, "", source)
    if (source !~ /^\/srv\// && source != "/etc/timezone" && source != "/etc/localtime") {
      print "unexpected host mount: " source
      bad = 1
    }
  }
  END { exit bad }
' compose/docker-compose.yml

python3 -m py_compile compose/apps/sample-app/app.py

awk '
  /^[A-Za-z0-9_.-]+==[0-9][A-Za-z0-9_.!+-]*$/ { next }
  { print "un-pinned requirement: " $0; bad = 1 }
  END { exit bad }
' compose/apps/sample-app/requirements.txt

grep -q 'http://campsites' compose/caddy/Caddyfile
grep -q 'handle_path /campsites' compose/caddy/Caddyfile
grep -q 'ENABLE_MDNS=0' bootstrap/env.example
grep -q 'DISABLE_LID_SLEEP=1' bootstrap/env.example
grep -q 'GITEA_BOOTSTRAP=0' bootstrap/env.example
grep -q 'GITEA_ADMIN_EMAIL=' bootstrap/env.example
grep -q 'GITEA_ADMIN_PASSWORD=' bootstrap/env.example
grep -q 'JELLYFIN_BOOTSTRAP=0' bootstrap/env.example
grep -q 'JELLYFIN_ADMIN_PASSWORD=' bootstrap/env.example
grep -q 'avahi-daemon' bootstrap/bootstrap.sh
grep -q 'dnsutils' bootstrap/bootstrap.sh
grep -q 'ethtool' bootstrap/bootstrap.sh
grep -q 'iputils-ping' bootstrap/bootstrap.sh
grep -q 'iw' bootstrap/bootstrap.sh
grep -q 'mtr-tiny' bootstrap/bootstrap.sh
grep -q 'traceroute' bootstrap/bootstrap.sh
grep -q 'HandleLidSwitch=ignore' bootstrap/bootstrap.sh
grep -q 'systemctl enable --now docker' bootstrap/bootstrap.sh
! grep -R "loginctl show-logind" README.md docs
grep -q 'systemd-analyze cat-config systemd/logind.conf' README.md
grep -q 'systemd-analyze cat-config systemd/logind.conf' docs/commissioning.md
grep -q 'systemd-analyze cat-config systemd/logind.conf' docs/operations.md
grep -q 'bootstrap_gitea_admin' bootstrap/bootstrap.sh
grep -q 'bootstrap_jellyfin' bootstrap/bootstrap.sh
grep -q '/Startup/User' bootstrap/bootstrap.sh
grep -q '/Library/VirtualFolders' bootstrap/bootstrap.sh

awk '
  $1 == "FROM" && $2 ~ /:latest$/ { print "floating Dockerfile base image: " $2; bad = 1 }
  $1 == "FROM" && $2 !~ /@sha256:[a-f0-9]{64}$/ {
    print "Dockerfile base image missing digest pin: " $2
    bad = 1
  }
  END { exit bad }
' compose/apps/sample-app/Dockerfile

printf 'static repo checks: ok\n'
