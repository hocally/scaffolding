# Operations

## Common Commands

Status:

```bash
COMPOSE_DIR=/srv/compose ./scripts/status.sh
```

Logs:

```bash
COMPOSE_DIR=/srv/compose ./scripts/logs.sh
COMPOSE_DIR=/srv/compose ./scripts/logs.sh gitea
```

Validate:

```bash
COMPOSE_DIR=/srv/compose ./scripts/validate.sh
```

If local DNS records exist:

```bash
STRICT_DNS=1 COMPOSE_DIR=/srv/compose ./scripts/validate.sh
```

Network diagnostics:

```bash
./scripts/network-info.sh
```

Restart one service:

```bash
cd /srv/compose
sudo docker compose up -d gitea
```

Stop all services:

```bash
cd /srv/compose
sudo docker compose down
```

## Updates

External images are pinned by version tag and digest. Do not switch to `latest`, and do not drop the digest unless this is a deliberate upgrade.

Recommended upgrade path:

```bash
./scripts/upgrade_notes.sh
$EDITOR compose/docker-compose.yml
COMPOSE_DIR=compose ./scripts/validate.sh
```

On the server:

```bash
cd /srv/compose
sudo docker compose pull <service>
sudo docker compose up -d <service>
sudo docker compose logs --tail 100 <service>
```

Commit the changed image pin and any operational notes.

## Adding A Local App

1. Add a service to `compose/docker-compose.yml`.
2. Keep it on the `backend` network unless it truly needs direct LAN exposure.
3. Store persistent state under `/srv/data/apps/<app-name>`.
4. Add a route to `compose/caddy/Caddyfile`.
5. Add a local DNS record.
6. Run validation.

Before considering a new app done, add or update an acceptance test in `docs/acceptance-tests.md`.

## Manual Host Changes

Manual emergency changes are allowed, but backport them into this repo immediately. The repo should remain sufficient to rebuild the server from a clean Ubuntu install.

Host package versions installed by bootstrap are recorded in:

```text
/srv/compose/host-package-versions.txt
```

Use that file when debugging drift or reconstructing what changed between commissioning runs.
