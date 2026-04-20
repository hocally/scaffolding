#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${REPO_ROOT}"

tracked_files="$(git ls-files)"

bad_patterns=(
  "Hen""ry"
  "hen""ry"
  "O.?Call""aghan"
  "ocal""laghan"
  "gm""ail"
  "Mac""Book"
  "N""UC"
  "ee""ro"
  "blocked\\.ee""ro\\.com"
  "192\\.168\\.4"
  "wlp""2s0"
  "/Users/ho""cally"
  "/home/hen""ry"
  "sal""ads"
)

for pattern in "${bad_patterns[@]}"; do
  if rg -n -I "${pattern}" ${tracked_files}; then
    printf 'public sanitization test failed: matched private marker pattern: %s\n' "${pattern}" >&2
    exit 1
  fi
done

secret_patterns=(
  "BEGIN OPENSSH PRIVATE"" KEY"
  "BEGIN .*PRIVATE"" KEY"
  "ssh-ed""25519 "
  "ssh-r""sa "
)

for pattern in "${secret_patterns[@]}"; do
  if rg -n -I "${pattern}" ${tracked_files}; then
    printf 'public sanitization test failed: matched secret-like pattern: %s\n' "${pattern}" >&2
    exit 1
  fi
done

printf 'public sanitization tests: ok\n'
