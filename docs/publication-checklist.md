# Publication Checklist

Use this checklist before pushing the project to a public hosting service.

## Recommended Release Path

For the first public release, prefer a fresh no-history repository:

```bash
mkdir -p ../scaffolding-public
rsync -a \
  --exclude .git \
  --exclude bootstrap/env \
  --exclude 'bootstrap/*.pub' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  ./ ../scaffolding-public/

cd ../scaffolding-public
git init
git add .
git commit -m "Initial public home server scaffold"
```

This avoids publishing old commit author metadata, early experiments, or removed files.

## Required Checks

Run these from the repository root:

```bash
./tests/public_sanitization_tests.sh
./tests/static_repo_checks.sh
OFFLINE=1 COMPOSE_DIR=compose ./scripts/validate.sh
```

Expected result:

- no private markers or secret-like values are found in tracked files
- static repo checks pass
- offline Compose validation passes

## Manual Review

Before pushing, manually confirm:

- `bootstrap/env` is not tracked
- `bootstrap/*.pub` is not tracked
- no real admin email is present
- no real LAN subnet, router IP, hostname, or device nickname is present
- no private SSH key, token, password, or generated service data is present
- docs use generic terms such as server, laptop, router, and LAN client
