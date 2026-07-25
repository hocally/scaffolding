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

Check laptop lid policy:

```bash
systemd-analyze cat-config systemd/logind.conf | grep -E '^[[:space:]]*HandleLidSwitch(ExternalPower|Docked)?='
```

Expected result: all three values are `ignore`. If you intentionally want lid close to suspend again, set `DISABLE_LID_SLEEP=0` in `bootstrap/env` and rerun bootstrap.

Check boot and Wi-Fi recovery policy:

```bash
systemctl cat docker.service
systemctl is-enabled docker
systemctl is-active docker
ip -4 route
resolvectl status
```

Expected: the Docker unit declares `Wants=` and `After=` for `network-online.target`, Docker is `enabled` and `active`, and the host has a default route and DNS servers.

The bootstrap-installed networking diagnostics are `ip`, `iw`, `ethtool`, `ping`, `dig`, `mtr`, and `traceroute`. Wi-Fi credentials remain in Ubuntu's host-specific Netplan configuration and are not stored in this repository.

Restart one service:

```bash
cd /srv/compose
sudo docker compose up -d gitea
```

## Mainframe Dashboard

The Caddy default route serves the static service dashboard at `http://mainframe.local`. It links to Gitea at `/gitea/`, the sample app at `/campsites`, the optional Retro Waveform app at `/retro-waveform`, and Jellyfin at port `8096` on the hostname currently used in the browser.

The dashboard is intentionally static and served by Caddy; it adds no application runtime, database, or JavaScript dependency. Keep the host LAN-only.

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

## Adding A Container

Use [the container integration guide](container-integration.md) for every new
Compose-managed application. It covers service and state design, pinned images,
secrets, Caddy and dashboard integration, validation, deployment, and rollback.

Before considering a new app done, add or update an acceptance test in
`docs/acceptance-tests.md`.

## Retro Waveform Control Plane

Retro Waveform is optional and runs without hardware access in the initial Compose integration.
Build its local image from the checked-out application repository, then enable only its profile:

```bash
cd ~/retro-waveform
make image

cd /srv/compose
sudo docker compose --profile retro-waveform up -d retro-waveform
```

Use [compose/retro-waveform/README.md](../compose/retro-waveform/README.md) for the health
check, update, and rollback commands. Do not add USB devices, host networking, PipeWire sockets,
or `privileged` mode to this service until the hardware path has dedicated integration tests.

## Manual Host Changes

Manual emergency changes are allowed, but backport them into this repo immediately. The repo should remain sufficient to rebuild the server from a clean Ubuntu install.

Host package versions installed by bootstrap are recorded in:

```text
/srv/compose/host-package-versions.txt
```

Use that file when debugging drift or reconstructing what changed between commissioning runs.
