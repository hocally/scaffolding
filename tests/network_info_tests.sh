#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/network-info.sh
. "${REPO_ROOT}/scripts/network-info.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    printf 'network-info test failed: %s\n' "${description}" >&2
    printf 'expected:\n%s\n' "${expected}" >&2
    printf 'actual:\n%s\n' "${actual}" >&2
    exit 1
  fi
}

actual="$(
  printf '%s\n' \
    'Global:' \
    'Link 2 (wlan0): 192.168.50.1' |
    dns_servers_from_resolvectl_output
)"
assert_equal "192.168.50.1" "${actual}" "resolvectl link labels are ignored"

actual="$(
  printf '%s\n' \
    'Global: 2001:4860:4860::8888' \
    'Link 2 (eth0): 192.168.1.1 2606:4700:4700::1111' |
    dns_servers_from_resolvectl_output
)"
assert_equal "$(printf '%s\n%s\n%s' '192.168.1.1' '2001:4860:4860::8888' '2606:4700:4700::1111')" "${actual}" "IPv4 and IPv6 DNS servers are retained"

printf 'network-info tests: ok\n'
