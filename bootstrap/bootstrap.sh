#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=bootstrap/common.sh
. "${SCRIPT_DIR}/common.sh"

ENV_FILE="${BOOTSTRAP_ENV:-${SCRIPT_DIR}/env}"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
else
  warn "no bootstrap/env found; using defaults where safe"
fi

require_root
require_ubuntu_2404
require_supported_arch

SERVER_USER="$(detect_server_user)"
SERVER_GROUP="${SERVER_GROUP:-$(id -gn "${SERVER_USER}")}"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-$(hostname -s)}"
ENABLE_MDNS="${ENABLE_MDNS:-0}"
DISABLE_LID_SLEEP="${DISABLE_LID_SLEEP:-1}"
SERVICE_UID="$(id -u "${SERVER_USER}")"
SERVICE_GID="$(id -g "${SERVER_USER}")"
TZ="${TZ:-Etc/UTC}"
COMPOSE_TARGET_DIR="${COMPOSE_TARGET_DIR:-/srv/compose}"
START_SERVICES="${START_SERVICES:-1}"
LAN_IP=""
LAN_IFACE=""
LAN_GATEWAY=""
GITEA_ACCESS_HOST="${GITEA_ACCESS_HOST:-}"
GITEA_BOOTSTRAP="${GITEA_BOOTSTRAP:-0}"
GITEA_ADMIN_USERNAME="${GITEA_ADMIN_USERNAME:-}"
GITEA_ADMIN_EMAIL="${GITEA_ADMIN_EMAIL:-}"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:-}"
GITEA_ADMIN_SSH_PUBLIC_KEY_FILE="${GITEA_ADMIN_SSH_PUBLIC_KEY_FILE:-}"
GITEA_BOOTSTRAP_REPO="${GITEA_BOOTSTRAP_REPO:-}"
GITEA_ADMIN_SSH_PUBLIC_KEY_PATH=""
JELLYFIN_BOOTSTRAP="${JELLYFIN_BOOTSTRAP:-0}"
JELLYFIN_ADMIN_USERNAME="${JELLYFIN_ADMIN_USERNAME:-}"
JELLYFIN_ADMIN_PASSWORD="${JELLYFIN_ADMIN_PASSWORD:-}"
JELLYFIN_SERVER_NAME="${JELLYFIN_SERVER_NAME:-${SERVER_HOSTNAME:-}}"
JELLYFIN_UI_CULTURE="${JELLYFIN_UI_CULTURE:-en-US}"
JELLYFIN_METADATA_LANGUAGE="${JELLYFIN_METADATA_LANGUAGE:-en}"
JELLYFIN_METADATA_COUNTRY="${JELLYFIN_METADATA_COUNTRY:-US}"
JELLYFIN_CREATE_DEFAULT_LIBRARIES="${JELLYFIN_CREATE_DEFAULT_LIBRARIES:-1}"
JELLYFIN_MOVIES_LIBRARY_NAME="${JELLYFIN_MOVIES_LIBRARY_NAME:-Movies}"
JELLYFIN_MOVIES_LIBRARY_PATH="${JELLYFIN_MOVIES_LIBRARY_PATH:-/media/movies}"
JELLYFIN_TV_LIBRARY_NAME="${JELLYFIN_TV_LIBRARY_NAME:-TV}"
JELLYFIN_TV_LIBRARY_PATH="${JELLYFIN_TV_LIBRARY_PATH:-/media/tv}"
JELLYFIN_MUSIC_LIBRARY_NAME="${JELLYFIN_MUSIC_LIBRARY_NAME:-Music}"
JELLYFIN_MUSIC_LIBRARY_PATH="${JELLYFIN_MUSIC_LIBRARY_PATH:-/media/music}"

print_commissioning_summary() {
  log "commissioning summary"
  printf '  hostname: %s\n' "${SERVER_HOSTNAME}"
  printf '  operator user: %s\n' "${SERVER_USER}"
  printf '  operator group: %s\n' "${SERVER_GROUP}"
  printf '  architecture: %s\n' "$(dpkg --print-architecture)"
  printf '  primary interface: %s\n' "${LAN_IFACE:-unknown}"
  printf '  primary IPv4: %s\n' "${LAN_IP:-unknown}"
  printf '  default gateway: %s\n' "${LAN_GATEWAY:-unknown}"
  printf '  compose target: %s\n' "${COMPOSE_TARGET_DIR}"
  printf '  mDNS name: %s\n' "$(if [[ "${ENABLE_MDNS}" == "1" ]]; then printf '%s.local' "${SERVER_HOSTNAME}"; else printf 'disabled'; fi)"
  printf '  lid sleep disabled: %s\n' "$(if [[ "${DISABLE_LID_SLEEP}" == "1" ]]; then printf 'yes'; else printf 'no'; fi)"
  printf '  Gitea bootstrap: %s\n' "$(if [[ "${GITEA_BOOTSTRAP}" == "1" ]]; then printf 'enabled'; else printf 'disabled'; fi)"
  printf '  Jellyfin bootstrap: %s\n' "$(if [[ "${JELLYFIN_BOOTSTRAP}" == "1" ]]; then printf 'enabled'; else printf 'disabled'; fi)"
  printf '\n'
  printf 'Router task after bootstrap:\n'
  printf '  1. Create a DHCP reservation for this machine at %s.\n' "${LAN_IP:-the detected server IP}"
  printf '  2. Add local DNS records: gitea -> %s, campsites -> %s.\n' "${LAN_IP:-server IP}" "${LAN_IP:-server IP}"
  if [[ "${ENABLE_MDNS}" == "1" ]]; then
    printf '  3. If bare DNS names are unavailable, try mDNS: http://%s.local\n' "${SERVER_HOSTNAME}"
  fi
  printf '\n'
}

install_host_packages() {
  log "installing host prerequisites"
  apt-get update || die_action "apt-get update failed" "verify internet access and DNS on the server, then rerun bootstrap"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    dnsutils \
    ethtool \
    git \
    gnupg \
    iproute2 \
    iputils-ping \
    iw \
    lsb-release \
    mtr-tiny \
    rsync \
    traceroute || die_action "failed to install host prerequisites" "inspect apt output above, fix package manager errors, then rerun bootstrap"
}

configure_mdns() {
  if [[ "${ENABLE_MDNS}" != "1" ]]; then
    log "ENABLE_MDNS=${ENABLE_MDNS}; skipping Avahi mDNS setup"
    return
  fi

  if [[ "$(hostname -s)" != "${SERVER_HOSTNAME}" ]]; then
    log "setting host hostname to ${SERVER_HOSTNAME}"
    hostnamectl set-hostname "${SERVER_HOSTNAME}" || die_action "failed to set hostname to ${SERVER_HOSTNAME}" "run hostnamectl status, fix hostname configuration, then rerun bootstrap"
  fi

  log "installing and enabling Avahi for mDNS name ${SERVER_HOSTNAME}.local"
  DEBIAN_FRONTEND=noninteractive apt-get install -y avahi-daemon || die_action "failed to install avahi-daemon" "inspect apt output above, fix package manager errors, then rerun bootstrap"
  systemctl enable --now avahi-daemon || die_action "failed to enable or start avahi-daemon" "check: systemctl status avahi-daemon"
}

configure_lid_sleep() {
  local lid_conf="/etc/systemd/logind.conf.d/10-home-server-lid.conf"

  if [[ "${DISABLE_LID_SLEEP}" != "1" ]]; then
    if [[ -f "${lid_conf}" ]]; then
      log "DISABLE_LID_SLEEP=${DISABLE_LID_SLEEP}; removing home server lid policy"
      rm -f "${lid_conf}"
      systemctl restart systemd-logind || die_action "failed to restart systemd-logind after removing lid policy" "check: systemctl status systemd-logind"
    else
      log "DISABLE_LID_SLEEP=${DISABLE_LID_SLEEP}; leaving systemd-logind lid behavior unchanged"
    fi
    return
  fi

  log "configuring systemd-logind to ignore lid close events"
  install -d -m 0755 /etc/systemd/logind.conf.d
  cat > "${lid_conf}" <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF

  systemctl restart systemd-logind || die_action "failed to restart systemd-logind after lid policy update" "check: systemctl status systemd-logind"
}

install_docker() {
  if have_cmd docker && docker compose version >/dev/null 2>&1; then
    log "Docker Engine and Compose plugin already available"
  else
    log "installing Docker Engine from Docker's official apt repository"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || die_action "failed to download Docker apt signing key" "verify the server can reach https://download.docker.com, then rerun bootstrap"
    chmod a+r /etc/apt/keyrings/docker.asc

    local codename
    codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME}")"

    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
      "$(dpkg --print-architecture)" \
      "${codename}" > /etc/apt/sources.list.d/docker.list

    apt-get update || die_action "apt-get update failed after adding Docker repository" "check /etc/apt/sources.list.d/docker.list and internet connectivity, then rerun bootstrap"
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin || die_action "failed to install Docker Engine or Compose plugin" "inspect apt output above, then rerun bootstrap after fixing package errors"
  fi

  systemctl enable --now docker || die_action "failed to enable or start Docker" "check: systemctl status docker"
}

validate_gitea_bootstrap_config() {
  if [[ "${GITEA_BOOTSTRAP}" != "1" ]]; then
    return
  fi

  [[ -n "${GITEA_ADMIN_USERNAME}" ]] || die_action "GITEA_BOOTSTRAP=1 but GITEA_ADMIN_USERNAME is empty" "edit bootstrap/env and set the Gitea admin username"
  [[ -n "${GITEA_ADMIN_EMAIL}" ]] || die_action "GITEA_BOOTSTRAP=1 but GITEA_ADMIN_EMAIL is empty" "edit bootstrap/env and set the Gitea admin email"
  [[ -n "${GITEA_ADMIN_PASSWORD}" ]] || die_action "GITEA_BOOTSTRAP=1 but GITEA_ADMIN_PASSWORD is empty" "edit bootstrap/env, set a temporary admin password, and store it in your password manager before bootstrap clears it"

  if [[ -n "${GITEA_BOOTSTRAP_REPO}" ]] && ! valid_gitea_repo_name "${GITEA_BOOTSTRAP_REPO}"; then
    die_action "GITEA_BOOTSTRAP_REPO '${GITEA_BOOTSTRAP_REPO}' is not a safe repository name" "use only letters, numbers, dots, underscores, and hyphens; do not start/end with a dot or include '..'"
  fi

  if [[ -n "${GITEA_ADMIN_SSH_PUBLIC_KEY_FILE}" ]]; then
    GITEA_ADMIN_SSH_PUBLIC_KEY_PATH="$(resolve_operator_path "${REPO_ROOT}" "${GITEA_ADMIN_SSH_PUBLIC_KEY_FILE}")"
    [[ -r "${GITEA_ADMIN_SSH_PUBLIC_KEY_PATH}" ]] || die_action "cannot read GITEA_ADMIN_SSH_PUBLIC_KEY_FILE at ${GITEA_ADMIN_SSH_PUBLIC_KEY_PATH}" "fix the path in bootstrap/env or leave it blank"
  fi
}

validate_jellyfin_bootstrap_config() {
  if [[ "${JELLYFIN_BOOTSTRAP}" != "1" ]]; then
    return
  fi

  [[ -n "${JELLYFIN_ADMIN_USERNAME}" ]] || die_action "JELLYFIN_BOOTSTRAP=1 but JELLYFIN_ADMIN_USERNAME is empty" "edit bootstrap/env and set the Jellyfin admin username"
  [[ -n "${JELLYFIN_ADMIN_PASSWORD}" ]] || die_action "JELLYFIN_BOOTSTRAP=1 but JELLYFIN_ADMIN_PASSWORD is empty" "edit bootstrap/env, set a temporary admin password, and store it in your password manager before bootstrap clears it"
  [[ -n "${JELLYFIN_SERVER_NAME}" ]] || JELLYFIN_SERVER_NAME="${SERVER_HOSTNAME}"
}

random_secret() {
  head -c 48 /dev/urandom | base64 | tr -d '\n'
}

create_srv_layout() {
  log "creating /srv directory layout"
  install -d -m 0755 \
    /srv \
    "${COMPOSE_TARGET_DIR}" \
    /srv/data \
    /srv/data/caddy/data \
    /srv/data/caddy/config \
    /srv/data/gitea \
    /srv/data/jellyfin/config \
    /srv/data/jellyfin/cache \
    /srv/data/apps \
    /srv/media/movies \
    /srv/media/tv \
    /srv/media/music \
    /srv/backups

  chown -R "${SERVER_USER}:${SERVER_GROUP}" \
    "${COMPOSE_TARGET_DIR}" \
    /srv/data \
    /srv/media \
    /srv/backups
}

install_compose_bundle() {
  log "syncing compose bundle to ${COMPOSE_TARGET_DIR}"
  local gitea_access_host="${GITEA_ACCESS_HOST:-${LAN_IP}}"

  if [[ -z "${gitea_access_host}" ]]; then
    die_action "cannot determine Gitea access host" "set GITEA_ACCESS_HOST in bootstrap/env or fix IPv4 detection"
  fi

  rsync -a \
    --exclude '.env' \
    "${REPO_ROOT}/compose/" \
    "${COMPOSE_TARGET_DIR}/"

  if [[ ! -f "${COMPOSE_TARGET_DIR}/.env" ]]; then
    log "creating ${COMPOSE_TARGET_DIR}/.env from example"
    cp "${REPO_ROOT}/compose/.env.example" "${COMPOSE_TARGET_DIR}/.env"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "SERVER_HOSTNAME" "${SERVER_HOSTNAME}"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "HOST_LAN_IP" "${LAN_IP}"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "TZ" "${TZ}"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "SERVICE_UID" "${SERVICE_UID}"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "SERVICE_GID" "${SERVICE_GID}"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "GITEA_DOMAIN" "${gitea_access_host}"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "GITEA_ROOT_URL" "http://${gitea_access_host}/"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "GITEA_SSH_DOMAIN" "${gitea_access_host}"
    chown "${SERVER_USER}:${SERVER_GROUP}" "${COMPOSE_TARGET_DIR}/.env"
    chmod 0640 "${COMPOSE_TARGET_DIR}/.env"
  else
    log "leaving existing ${COMPOSE_TARGET_DIR}/.env unchanged"
  fi

  if [[ "${GITEA_BOOTSTRAP}" == "1" ]]; then
    log "GITEA_BOOTSTRAP=1; forcing registration disabled in ${COMPOSE_TARGET_DIR}/.env"
    set_env_value "${COMPOSE_TARGET_DIR}/.env" "GITEA_DISABLE_REGISTRATION" "true"
  fi

  chown -R "${SERVER_USER}:${SERVER_GROUP}" "${COMPOSE_TARGET_DIR}"
}

render_gitea_app_ini() {
  if [[ "${GITEA_BOOTSTRAP}" != "1" ]]; then
    return
  fi

  local app_ini="/srv/data/gitea/gitea/conf/app.ini"
  if [[ -f "${app_ini}" ]] && grep -Eq '^[[:space:]]*INSTALL_LOCK[[:space:]]*=[[:space:]]*true[[:space:]]*$' "${app_ini}"; then
    log "Gitea already has an installed app.ini; leaving it unchanged"
    return
  fi

  local gitea_access_host="${GITEA_ACCESS_HOST:-${LAN_IP}}"
  local gitea_ssh_port="${GITEA_SSH_PORT:-2222}"

  log "preseeding Gitea app.ini for non-interactive first start"
  install -d -m 0755 /srv/data/gitea/gitea/conf
  cat > "${app_ini}" <<EOF
APP_NAME = Gitea: Git with a cup of tea
RUN_MODE = prod
RUN_USER = git
WORK_PATH = /data/gitea

[repository]
ROOT = /data/git/repositories

[repository.local]
LOCAL_COPY_PATH = /data/gitea/tmp/local-repo

[repository.upload]
TEMP_PATH = /data/gitea/uploads

[server]
APP_DATA_PATH = /data/gitea
DOMAIN = ${gitea_access_host}
SSH_DOMAIN = ${gitea_access_host}
HTTP_PORT = 3000
ROOT_URL = http://${gitea_access_host}/
DISABLE_SSH = false
SSH_PORT = ${gitea_ssh_port}
SSH_LISTEN_PORT = 22
LFS_START_SERVER = true
OFFLINE_MODE = true

[database]
PATH = /data/gitea/gitea.db
DB_TYPE = sqlite3
LOG_SQL = false

[indexer]
ISSUE_INDEXER_PATH = /data/gitea/indexers/issues.bleve

[session]
PROVIDER = file
PROVIDER_CONFIG = /data/gitea/sessions

[picture]
AVATAR_UPLOAD_PATH = /data/gitea/avatars
REPOSITORY_AVATAR_UPLOAD_PATH = /data/gitea/repo-avatars

[attachment]
PATH = /data/gitea/attachments

[log]
MODE = console
LEVEL = info
ROOT_PATH = /data/gitea/log

[security]
INSTALL_LOCK = true
SECRET_KEY = $(random_secret)
INTERNAL_TOKEN = $(random_secret)
PASSWORD_HASH_ALGO = pbkdf2

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL = false

[lfs]
PATH = /data/git/lfs

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[mailer]
ENABLED = false

[cron.update_checker]
ENABLED = false

[repository.pull-request]
DEFAULT_MERGE_STYLE = merge

[repository.signing]
DEFAULT_TRUST_MODEL = committer

[oauth2]
JWT_SECRET = $(random_secret)

EOF

  chown -R "${SERVICE_UID}:${SERVICE_GID}" /srv/data/gitea
  chmod 0644 "${app_ini}"
}

write_host_manifest() {
  local manifest="${COMPOSE_TARGET_DIR}/host-package-versions.txt"

  log "writing host package manifest to ${manifest}"
  {
    printf 'generated_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf 'kernel=%s\n' "$(uname -a)"
    printf 'architecture=%s\n' "$(dpkg --print-architecture)"
    printf '\n[os-release]\n'
    cat /etc/os-release
    printf '\n[packages]\n'
    {
      dpkg-query -W -f='${Package}=${Version}\n' \
        avahi-daemon \
        ca-certificates \
        containerd.io \
        curl \
        dnsutils \
        ethtool \
        docker-buildx-plugin \
        docker-ce \
        docker-ce-cli \
        docker-compose-plugin \
        git \
        gnupg \
        iproute2 \
        iputils-ping \
        iw \
        lsb-release \
        mtr-tiny \
        rsync \
        traceroute 2>/dev/null || true
    } | sort
  } > "${manifest}"

  chown "${SERVER_USER}:${SERVER_GROUP}" "${manifest}"
  chmod 0644 "${manifest}"
}

configure_operator_access() {
  if id -nG "${SERVER_USER}" | tr ' ' '\n' | grep -qx docker; then
    log "${SERVER_USER} is already in docker group"
  else
    log "adding ${SERVER_USER} to docker group"
    usermod -aG docker "${SERVER_USER}"
    warn "${SERVER_USER} must log out and back in before using docker without sudo"
  fi
}

start_services() {
  if [[ "${START_SERVICES}" != "1" ]]; then
    log "START_SERVICES=${START_SERVICES}; skipping docker compose up"
    return
  fi

  log "starting services"
  (
    cd "${COMPOSE_TARGET_DIR}"
    docker compose --env-file .env up -d --build
  )
}

wait_for_gitea() {
  local attempt

  for attempt in $(seq 1 60); do
    if docker exec gitea wget --spider -q http://127.0.0.1:3000/api/healthz >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done

  die_action "Gitea did not become healthy after bootstrap start" "inspect logs with: COMPOSE_DIR=${COMPOSE_TARGET_DIR} ${REPO_ROOT}/scripts/logs.sh gitea"
}

gitea_admin_user_exists() {
  docker exec --user git gitea gitea admin user list 2>/dev/null |
    awk -v username="${GITEA_ADMIN_USERNAME}" 'NR > 1 && $2 == username { found = 1 } END { exit found ? 0 : 1 }'
}

gitea_api() {
  local method="$1"
  local path="$2"
  shift 2

  curl -fsS \
    --user "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PASSWORD}" \
    --request "${method}" \
    "http://127.0.0.1:80${path}" \
    "$@"
}

bootstrap_gitea_admin() {
  if [[ "${GITEA_BOOTSTRAP}" != "1" ]]; then
    return
  fi

  log "waiting for Gitea to accept admin bootstrap commands"
  wait_for_gitea

  if gitea_admin_user_exists; then
    log "Gitea admin user ${GITEA_ADMIN_USERNAME} already exists"
  else
    log "creating Gitea admin user ${GITEA_ADMIN_USERNAME}"
    docker exec --user git gitea gitea admin user create \
      --username "${GITEA_ADMIN_USERNAME}" \
      --password "${GITEA_ADMIN_PASSWORD}" \
      --email "${GITEA_ADMIN_EMAIL}" \
      --admin \
      --must-change-password=false || die_action "failed to create Gitea admin user" "inspect Gitea logs and rerun bootstrap after fixing the cause"
  fi

  if [[ -n "${GITEA_ADMIN_SSH_PUBLIC_KEY_PATH}" ]]; then
    local ssh_public_key
    ssh_public_key="$(awk '{ print $1 " " $2; exit }' "${GITEA_ADMIN_SSH_PUBLIC_KEY_PATH}")"
    if gitea_api GET /api/v1/user/keys | grep -Fq "${ssh_public_key}"; then
      log "Gitea admin SSH key is already present"
    else
      log "adding SSH public key to Gitea admin user"
      gitea_api POST /api/v1/user/keys \
        -H 'Content-Type: application/json' \
        --data "{\"title\":\"bootstrap-${SERVER_HOSTNAME}\",\"key\":\"${ssh_public_key}\"}" >/dev/null ||
        die_action "failed to add Gitea admin SSH key" "verify GITEA_ADMIN_PASSWORD and GITEA_ADMIN_SSH_PUBLIC_KEY_FILE, then rerun bootstrap"
    fi
  fi

  if [[ -n "${GITEA_BOOTSTRAP_REPO}" ]]; then
    local repo_status
    repo_status="$(curl -sS -o /dev/null -w '%{http_code}' \
      --user "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PASSWORD}" \
      "http://127.0.0.1:80/api/v1/repos/${GITEA_ADMIN_USERNAME}/${GITEA_BOOTSTRAP_REPO}")"

    if [[ "${repo_status}" == "200" ]]; then
      log "Gitea bootstrap repo ${GITEA_ADMIN_USERNAME}/${GITEA_BOOTSTRAP_REPO} already exists"
    else
      log "creating Gitea bootstrap repo ${GITEA_ADMIN_USERNAME}/${GITEA_BOOTSTRAP_REPO}"
      gitea_api POST /api/v1/user/repos \
        -H 'Content-Type: application/json' \
        --data "{\"name\":\"${GITEA_BOOTSTRAP_REPO}\",\"private\":true,\"auto_init\":true}" >/dev/null ||
        die_action "failed to create Gitea bootstrap repo" "inspect Gitea logs and rerun bootstrap after fixing the cause"
    fi
  fi

  if [[ -f "${ENV_FILE}" ]]; then
    log "clearing one-time GITEA_ADMIN_EMAIL/GITEA_ADMIN_PASSWORD and disabling GITEA_BOOTSTRAP in ${ENV_FILE}"
    set_env_value "${ENV_FILE}" "GITEA_ADMIN_EMAIL" ""
    set_env_value "${ENV_FILE}" "GITEA_ADMIN_PASSWORD" ""
    set_env_value "${ENV_FILE}" "GITEA_BOOTSTRAP" "0"
    chown "${SERVER_USER}:${SERVER_GROUP}" "${ENV_FILE}"
    chmod 0600 "${ENV_FILE}"
  fi
}

wait_for_jellyfin() {
  local attempt

  for attempt in $(seq 1 60); do
    if curl -fsS --max-time 5 http://127.0.0.1:8096/Startup/Configuration >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done

  die_action "Jellyfin did not become reachable after bootstrap start" "inspect logs with: COMPOSE_DIR=${COMPOSE_TARGET_DIR} ${REPO_ROOT}/scripts/logs.sh jellyfin"
}

jellyfin_startup_completed() {
  curl -fsS --max-time 5 http://127.0.0.1:8096/System/Info/Public |
    grep -q '"StartupWizardCompleted":true'
}

jellyfin_api() {
  local method="$1"
  local path="$2"
  local token="$3"
  shift 3

  curl -fsS \
    --request "${method}" \
    -H "X-Emby-Token: ${token}" \
    "http://127.0.0.1:8096${path}" \
    "$@"
}

jellyfin_auth_token() {
  local username password response
  username="$(json_escape "${JELLYFIN_ADMIN_USERNAME}")"
  password="$(json_escape "${JELLYFIN_ADMIN_PASSWORD}")"

  response="$(curl -fsS \
    --request POST \
    -H 'Content-Type: application/json' \
    -H 'X-Emby-Authorization: MediaBrowser Client="Bootstrap", Device="Bootstrap", DeviceId="bootstrap", Version="1.0.0"' \
    --data "{\"Username\":\"${username}\",\"Pw\":\"${password}\"}" \
    http://127.0.0.1:8096/Users/AuthenticateByName)"

  printf '%s\n' "${response}" |
    sed -n 's/.*"AccessToken":"\([^"]*\)".*/\1/p'
}

bootstrap_jellyfin_startup() {
  local username password server_name ui_culture metadata_language metadata_country

  username="$(json_escape "${JELLYFIN_ADMIN_USERNAME}")"
  password="$(json_escape "${JELLYFIN_ADMIN_PASSWORD}")"
  server_name="$(json_escape "${JELLYFIN_SERVER_NAME}")"
  ui_culture="$(json_escape "${JELLYFIN_UI_CULTURE}")"
  metadata_language="$(json_escape "${JELLYFIN_METADATA_LANGUAGE}")"
  metadata_country="$(json_escape "${JELLYFIN_METADATA_COUNTRY}")"

  log "initializing Jellyfin startup user record"
  curl -fsS http://127.0.0.1:8096/Startup/User >/dev/null ||
    die_action "failed to initialize Jellyfin startup user" "inspect Jellyfin logs and rerun bootstrap after fixing the cause"

  log "configuring Jellyfin startup wizard settings"
  curl -fsS \
    --request POST \
    -H 'Content-Type: application/json' \
    --data "{\"ServerName\":\"${server_name}\",\"UICulture\":\"${ui_culture}\",\"MetadataCountryCode\":\"${metadata_country}\",\"PreferredMetadataLanguage\":\"${metadata_language}\"}" \
    http://127.0.0.1:8096/Startup/Configuration >/dev/null ||
    die_action "failed to configure Jellyfin startup settings" "inspect Jellyfin logs and rerun bootstrap after fixing the cause"

  log "creating Jellyfin admin user ${JELLYFIN_ADMIN_USERNAME}"
  curl -fsS \
    --request POST \
    -H 'Content-Type: application/json' \
    --data "{\"Name\":\"${username}\",\"Password\":\"${password}\"}" \
    http://127.0.0.1:8096/Startup/User >/dev/null ||
    die_action "failed to create Jellyfin startup admin user" "inspect Jellyfin logs and rerun bootstrap after fixing the cause"

  log "marking Jellyfin startup wizard complete"
  curl -fsS \
    --request POST \
    http://127.0.0.1:8096/Startup/Complete >/dev/null ||
    die_action "failed to complete Jellyfin startup wizard" "inspect Jellyfin logs and rerun bootstrap after fixing the cause"
}

jellyfin_library_exists() {
  local token="$1"
  local name="$2"
  local escaped_name

  escaped_name="$(json_escape "${name}")"

  jellyfin_api GET /Library/VirtualFolders "${token}" |
    grep -Fq "\"Name\":\"${escaped_name}\""
}

ensure_jellyfin_library() {
  local token="$1"
  local name="$2"
  local collection_type="$3"
  local path="$4"
  local encoded_name encoded_type escaped_path metadata_language metadata_country

  [[ -n "${name}" && -n "${path}" ]] || return

  if jellyfin_library_exists "${token}" "${name}"; then
    log "Jellyfin library ${name} already exists"
    return
  fi

  encoded_name="$(urlencode "${name}")"
  encoded_type="$(urlencode "${collection_type}")"
  escaped_path="$(json_escape "${path}")"
  metadata_language="$(json_escape "${JELLYFIN_METADATA_LANGUAGE}")"
  metadata_country="$(json_escape "${JELLYFIN_METADATA_COUNTRY}")"

  log "creating Jellyfin library ${name} at ${path}"
  jellyfin_api POST "/Library/VirtualFolders?name=${encoded_name}&collectionType=${encoded_type}&refreshLibrary=false" "${token}" \
    -H 'Content-Type: application/json' \
    --data "{\"LibraryOptions\":{\"Enabled\":true,\"EnableRealtimeMonitor\":true,\"EnableLUFSScan\":false,\"EnableChapterImageExtraction\":false,\"ExtractChapterImagesDuringLibraryScan\":false,\"EnableTrickplayImageExtraction\":false,\"ExtractTrickplayImagesDuringLibraryScan\":false,\"PathInfos\":[{\"Path\":\"${escaped_path}\"}],\"SaveLocalMetadata\":false,\"PreferredMetadataLanguage\":\"${metadata_language}\",\"MetadataCountryCode\":\"${metadata_country}\"}}" >/dev/null ||
    die_action "failed to create Jellyfin library ${name}" "inspect Jellyfin logs and rerun bootstrap after fixing the cause"
}

bootstrap_jellyfin() {
  local token

  if [[ "${JELLYFIN_BOOTSTRAP}" != "1" ]]; then
    return
  fi

  log "waiting for Jellyfin startup API"
  wait_for_jellyfin

  if jellyfin_startup_completed; then
    log "Jellyfin startup wizard is already complete"
  else
    bootstrap_jellyfin_startup
  fi

  token="$(jellyfin_auth_token)"
  [[ -n "${token}" ]] || die_action "failed to authenticate to Jellyfin after bootstrap" "verify JELLYFIN_ADMIN_USERNAME and JELLYFIN_ADMIN_PASSWORD, then rerun bootstrap"

  if [[ "${JELLYFIN_CREATE_DEFAULT_LIBRARIES}" == "1" ]]; then
    ensure_jellyfin_library "${token}" "${JELLYFIN_MOVIES_LIBRARY_NAME}" "movies" "${JELLYFIN_MOVIES_LIBRARY_PATH}"
    ensure_jellyfin_library "${token}" "${JELLYFIN_TV_LIBRARY_NAME}" "tvshows" "${JELLYFIN_TV_LIBRARY_PATH}"
    ensure_jellyfin_library "${token}" "${JELLYFIN_MUSIC_LIBRARY_NAME}" "music" "${JELLYFIN_MUSIC_LIBRARY_PATH}"
  fi

  if [[ -f "${ENV_FILE}" ]]; then
    log "clearing one-time JELLYFIN_ADMIN_PASSWORD and disabling JELLYFIN_BOOTSTRAP in ${ENV_FILE}"
    set_env_value "${ENV_FILE}" "JELLYFIN_ADMIN_PASSWORD" ""
    set_env_value "${ENV_FILE}" "JELLYFIN_BOOTSTRAP" "0"
    chown "${SERVER_USER}:${SERVER_GROUP}" "${ENV_FILE}"
    chmod 0600 "${ENV_FILE}"
  fi
}

main() {
  require_network_basics
  LAN_IP="$(primary_ipv4)"
  LAN_IFACE="$(default_iface)"
  LAN_GATEWAY="$(default_gateway)"
  validate_gitea_bootstrap_config
  validate_jellyfin_bootstrap_config
  print_commissioning_summary
  install_host_packages
  configure_mdns
  configure_lid_sleep
  install_docker
  create_srv_layout
  install_compose_bundle
  render_gitea_app_ini
  write_host_manifest
  configure_operator_access
  start_services
  bootstrap_gitea_admin
  bootstrap_jellyfin

  log "bootstrap complete"
  log "review ${COMPOSE_TARGET_DIR}/.env and run: COMPOSE_DIR=${COMPOSE_TARGET_DIR} ${REPO_ROOT}/scripts/validate.sh"
  log "after router DNS is configured, run: STRICT_DNS=1 COMPOSE_DIR=${COMPOSE_TARGET_DIR} ${REPO_ROOT}/scripts/validate.sh"
}

main "$@"
