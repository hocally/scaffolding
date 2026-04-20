# Security

This project is designed for private LAN services. Do not expose services to the public internet unless you have intentionally reviewed the service, authentication, update, and backup posture.

## Secrets

Do not commit operator-owned secrets or host-local configuration.

Keep these files local:

- `bootstrap/env`
- `bootstrap/*.pub`
- `/srv/compose/.env`
- private SSH keys
- password-manager exports
- generated service data under `/srv/data`

The repository includes examples only. Fill real values on the target server, and let bootstrap clear one-time Gitea and Jellyfin bootstrap fields after setup.

## Public Fork Checklist

Before publishing a fork or template:

```bash
./tests/public_sanitization_tests.sh
./tests/static_repo_checks.sh
OFFLINE=1 COMPOSE_DIR=compose ./scripts/validate.sh
```

If this repository has ever contained personal commits, real host details, or private configuration, publish a fresh no-history copy instead of pushing the existing Git history.
