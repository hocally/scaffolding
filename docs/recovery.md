# Recovery

This document assumes the host failed and you are rebuilding on replacement hardware.

## Rebuild From Scratch

1. Install Ubuntu Server 24.04 LTS.
2. Restore or recreate the same operator account.
3. Clone this repo.
4. Run bootstrap:

```bash
cd ~/scaffolding
cp bootstrap/env.example bootstrap/env
$EDITOR bootstrap/env
sudo ./bootstrap/bootstrap.sh
```

5. Restore data into:

```text
/srv/data/gitea
/srv/data/jellyfin/config
/srv/media
```

6. Start services:

```bash
cd /srv/compose
sudo docker compose up -d
```

7. Validate:

```bash
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
```

If local DNS records exist:

```bash
STRICT_DNS=1 COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
```

8. Repeat the power-loss test in `docs/acceptance-tests.md`.

## Service-Specific Notes

Gitea state is under `/srv/data/gitea`. With the default SQLite setup, restoring that directory restores repositories, config, and database state.

Jellyfin state is under `/srv/data/jellyfin/config`. Jellyfin cache is under `/srv/data/jellyfin/cache`. Media is under `/srv/media`.

Caddy state is under `/srv/data/caddy`, but this day-1 plain HTTP setup has no certificates to preserve.

## If Compose Config Is Broken

Render the final Compose config:

```bash
cd /srv/compose
sudo docker compose config
```

Temporarily stop the stack:

```bash
sudo docker compose down
```

Fix `/srv/compose/docker-compose.yml` or `/srv/compose/.env`, then start again:

```bash
sudo docker compose up -d
```

Backport the fix into the repo.
