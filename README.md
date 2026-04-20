# Home Server Scaffold

This repository defines a small, reproducible home server for a compact x86_64 or arm64 machine running Ubuntu Server 24.04 LTS.

The first-pass architecture is intentionally boring:

- Ubuntu Server 24.04 LTS on the host
- Docker Engine plus the Docker Compose plugin for services
- explicit bind mounts under `/srv`
- Caddy for plain HTTP LAN reverse proxying
- Gitea for personal Git hosting
- Jellyfin for LAN media serving
- one sample Flask app route at `http://campsites`, with an IP fallback at `http://<server-ip>/campsites`

Recommended approach: run the host with a stable LAN IP or DHCP reservation, then map simple LAN names such as `gitea` and `campsites` to that IP in your router or local DNS. Alternative: use the server IP for day 1 and add a real LAN DNS service later.

## Repository Layout

```text
.
├── AGENTS.md
├── SECURITY.md
├── README.md
├── bootstrap/
│   ├── bootstrap.sh
│   ├── common.sh
│   └── env.example
├── compose/
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── caddy/
│   │   ├── Caddyfile
│   │   └── config/
│   │       └── .gitkeep
│   ├── gitea/
│   │   ├── README.md
│   │   └── app.ini.template
│   ├── jellyfin/
│   │   └── README.md
│   └── apps/
│       └── sample-app/
│           ├── Dockerfile
│           ├── README.md
│           ├── app.py
│           └── requirements.txt
├── scripts/
│   ├── common.sh
│   ├── logs.sh
│   ├── network-info.sh
│   ├── status.sh
│   ├── upgrade_notes.sh
│   └── validate.sh
├── tests/
│   └── static_repo_checks.sh
├── docs/
│   ├── acceptance-tests.md
│   ├── backup-plan.md
│   ├── commissioning.md
│   ├── day-2-wishlist.md
│   ├── network.md
│   ├── operations.md
│   ├── publication-checklist.md
│   ├── recovery.md
│   └── target-hardware-runbook.md
└── .gitignore
```

## Host Layout

The bootstrap script creates this host layout:

```text
/srv/compose
/srv/compose/host-package-versions.txt
/srv/data/caddy/data
/srv/data/caddy/config
/srv/data/gitea
/srv/data/jellyfin/config
/srv/data/jellyfin/cache
/srv/data/apps
/srv/media/movies
/srv/media/tv
/srv/media/music
/srv/backups
```

Persistent application state lives under `/srv/data`. Media lives under `/srv/media`. `/srv/backups` is reserved for a future real backup system; this repo does not pretend backups exist on day 1.

Container images are pinned by version tag and digest where they come from an external registry. Host apt packages are installed from Ubuntu and Docker repositories during bootstrap, then recorded in `/srv/compose/host-package-versions.txt`; they are intentionally not hard-pinned on day 1 because that would add package mirror/version maintenance before the server has proven itself.

## Quick Start On The Server

Run these commands on the Ubuntu Server host, not on a laptop:

```bash
git clone <this-repo-url> ~/scaffolding
cd ~/scaffolding
cp bootstrap/env.example bootstrap/env
$EDITOR bootstrap/env
sudo ./bootstrap/bootstrap.sh
```

After bootstrap, review `/srv/compose/.env`, then validate:

```bash
COMPOSE_DIR=/srv/compose ./scripts/validate.sh
```

For a cleaner rebuild, `bootstrap/env` can also automate Gitea first-run setup:

```text
GITEA_BOOTSTRAP=1
GITEA_ADMIN_USERNAME=<admin-user>
GITEA_ADMIN_EMAIL=<admin-email>
GITEA_ADMIN_PASSWORD=<one-time-password>
GITEA_ADMIN_SSH_PUBLIC_KEY_FILE=/home/<server-user>/.ssh/id_ed25519.pub
GITEA_BOOTSTRAP_REPO=init
```

On success, bootstrap creates the admin user, disables registration, optionally adds the SSH key and repo, then clears `GITEA_ADMIN_EMAIL` and `GITEA_ADMIN_PASSWORD` and sets `GITEA_BOOTSTRAP=0` in `bootstrap/env`.

`bootstrap/env` can also automate Jellyfin's first-run wizard and create default media libraries:

```text
JELLYFIN_BOOTSTRAP=1
JELLYFIN_ADMIN_USERNAME=<admin-user>
JELLYFIN_ADMIN_PASSWORD=<one-time-password>
JELLYFIN_SERVER_NAME=<server-name>
JELLYFIN_CREATE_DEFAULT_LIBRARIES=1
```

On success, bootstrap completes the startup wizard, creates the admin user, adds Movies, TV, and Music libraries under `/media`, then clears `JELLYFIN_ADMIN_PASSWORD` and sets `JELLYFIN_BOOTSTRAP=0` in `bootstrap/env`.

If you are checking the repo from a workstation without Docker, use offline validation:

```bash
OFFLINE=1 COMPOSE_DIR=compose ./scripts/validate.sh
```

## Day-1 Services

| Service | Access | Notes |
| --- | --- | --- |
| Caddy | `http://<server-ip>`, `http://gitea`, `http://campsites` | Plain HTTP LAN reverse proxy |
| Gitea | `http://<server-ip>`, optionally `http://gitea`, and SSH on port `2222` | Uses SQLite by default for low operational overhead |
| Jellyfin | `http://<server-ip>:8096` | Direct LAN access for media streaming |
| Sample app | `http://campsites` or `http://<server-ip>/campsites` | Tiny Flask app that demonstrates the local app pattern |

Day-2 work is tracked separately in [docs/day-2-wishlist.md](docs/day-2-wishlist.md). The top recommended follow-up is real backups with a restore test.

## Secrets And Operator-Supplied Values

Do not commit local env files or secrets. Operator-owned values are kept in:

- `bootstrap/env`
- `/srv/compose/.env`
- manually provisioned SSH keys

Gitea generates its own internal secrets during initial setup and stores them under `/srv/data/gitea`.

## Validation

Use narrow checks first:

```bash
bash -n bootstrap/bootstrap.sh bootstrap/common.sh scripts/*.sh
OFFLINE=1 COMPOSE_DIR=compose ./scripts/validate.sh
./tests/static_repo_checks.sh
```

On the actual server after bootstrap:

```bash
COMPOSE_DIR=/srv/compose ./scripts/validate.sh
COMPOSE_DIR=/srv/compose ./scripts/status.sh
COMPOSE_DIR=/srv/compose ./scripts/logs.sh caddy
```

If local DNS records exist, also run:

```bash
STRICT_DNS=1 COMPOSE_DIR=/srv/compose ./scripts/validate.sh
```

## Rollback Notes

The service layer is Docker Compose. To stop it:

```bash
cd /srv/compose
sudo docker compose down
```

This does not delete persistent data. Persistent data remains under `/srv/data` and `/srv/media`.

To remove the scaffolded service files:

```bash
sudo rm -rf /srv/compose
```

Do not remove `/srv/data`, `/srv/media`, or `/srv/backups` unless you intentionally want to delete service state, media, or future backups.
