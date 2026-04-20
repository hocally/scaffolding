#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v docker >/dev/null 2>&1; then
  printf 'docker is required for Jellyfin bootstrap API tests\n' >&2
  exit 1
fi

image="$(awk '$1 == "image:" && $2 ~ /^jellyfin\/jellyfin:/ { print $2; exit }' compose/docker-compose.yml)"
if [[ -z "${image}" ]]; then
  printf 'could not find Jellyfin image in compose/docker-compose.yml\n' >&2
  exit 1
fi

port="${JELLYFIN_TEST_PORT:-18096}"
container="jellyfin-bootstrap-api-test-$$"
tmp="$(mktemp -d)"

cleanup() {
  docker rm -f "${container}" >/dev/null 2>&1 || true
  rm -rf "${tmp}"
}
trap cleanup EXIT

mkdir -p \
  "${tmp}/config" \
  "${tmp}/cache" \
  "${tmp}/media/movies" \
  "${tmp}/media/tv" \
  "${tmp}/media/music"

docker run -d \
  --name "${container}" \
  --user "$(id -u):$(id -g)" \
  -p "127.0.0.1:${port}:8096" \
  -v "${tmp}/config:/config" \
  -v "${tmp}/cache:/cache" \
  -v "${tmp}/media:/media:ro" \
  "${image}" >/dev/null

base_url="http://127.0.0.1:${port}"

for _ in $(seq 1 90); do
  if curl -fsS --max-time 3 "${base_url}/Startup/Configuration" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

curl -fsS --max-time 10 "${base_url}/Startup/Configuration" >/dev/null
curl -fsS --max-time 10 "${base_url}/Startup/User" >/dev/null

curl -fsS --max-time 10 \
  --request POST \
  -H 'Content-Type: application/json' \
  --data '{"ServerName":"bootstrap-test","UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' \
  "${base_url}/Startup/Configuration" >/dev/null

curl -fsS --max-time 10 \
  --request POST \
  -H 'Content-Type: application/json' \
  --data '{"Name":"bootstrap","Password":"bootstrap-test-password"}' \
  "${base_url}/Startup/User" >/dev/null

curl -fsS --max-time 10 \
  --request POST \
  "${base_url}/Startup/Complete" >/dev/null

token="$(
  curl -fsS --max-time 10 \
    --request POST \
    -H 'Content-Type: application/json' \
    -H 'X-Emby-Authorization: MediaBrowser Client="BootstrapTest", Device="BootstrapTest", DeviceId="bootstrap-test", Version="1.0.0"' \
    --data '{"Username":"bootstrap","Pw":"bootstrap-test-password"}' \
    "${base_url}/Users/AuthenticateByName" |
    sed -n 's/.*"AccessToken":"\([^"]*\)".*/\1/p'
)"

if [[ -z "${token}" ]]; then
  printf 'failed to authenticate to disposable Jellyfin\n' >&2
  exit 1
fi

add_library() {
  local name="$1"
  local collection_type="$2"
  local path="$3"

  curl -fsS --max-time 20 \
    --request POST \
    -H "X-Emby-Token: ${token}" \
    -H 'Content-Type: application/json' \
    --data "{\"LibraryOptions\":{\"Enabled\":true,\"EnableRealtimeMonitor\":true,\"PathInfos\":[{\"Path\":\"${path}\"}],\"SaveLocalMetadata\":false,\"PreferredMetadataLanguage\":\"en\",\"MetadataCountryCode\":\"US\"}}" \
    "${base_url}/Library/VirtualFolders?name=${name}&collectionType=${collection_type}&refreshLibrary=false" >/dev/null
}

add_library Movies movies /media/movies
add_library TV tvshows /media/tv
add_library Music music /media/music

curl -fsS --max-time 10 "${base_url}/System/Info/Public" |
  grep -q '"StartupWizardCompleted":true'

libraries="$(
  curl -fsS --max-time 10 \
    -H "X-Emby-Token: ${token}" \
    "${base_url}/Library/VirtualFolders"
)"

for library in Movies TV Music; do
  if ! grep -q "\"Name\":\"${library}\"" <<<"${libraries}"; then
    printf 'missing Jellyfin library from API result: %s\n' "${library}" >&2
    exit 1
  fi
done

printf 'Jellyfin bootstrap API tests: ok\n'
