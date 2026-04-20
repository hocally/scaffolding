# Acceptance Tests

These tests define "complete" for the day-1 home server.

Run them twice:

1. after the first successful commissioning pass
2. after wiping the machine, reinstalling Ubuntu Server 24.04 LTS, cloning the repo, and rerunning bootstrap

The second pass is the rebuildability proof.

## Server Bootstrap

On the server:

```bash
git clone <repo-url> ~/scaffolding
cd ~/scaffolding
cp bootstrap/env.example bootstrap/env
$EDITOR bootstrap/env
sudo ./bootstrap/bootstrap.sh
```

Expected result:

- bootstrap prints the detected hostname, interface, LAN IP, and gateway
- bootstrap prints the router DNS/DHCP tasks
- Docker starts successfully
- Compose files are copied to `/srv/compose`
- persistent directories exist under `/srv/data` and `/srv/media`
- if Gitea or Jellyfin bootstrap is enabled, their one-time identity/password fields are cleared from `bootstrap/env` after successful setup

Validate on the server:

```bash
COMPOSE_DIR=/srv/compose ./scripts/validate.sh
```

After router DNS is configured:

```bash
STRICT_DNS=1 COMPOSE_DIR=/srv/compose ./scripts/validate.sh
```

If the router cannot provide local DNS records, strict DNS is not required for day 1. The IP-based fallback route must still work.

## LAN Client Tests

From a laptop on the same LAN:

```bash
curl -fsS http://<server-ip>/campsites
curl -I http://<server-ip>
ssh -p 2222 git@<server-ip>
```

Expected result:

- `http://<server-ip>/campsites` loads the sample Flask app
- `http://<server-ip>` returns the Gitea UI or setup page
- SSH reaches Gitea via `<server-ip>` on port `2222`; authentication may fail until keys are configured

If local DNS exists, also test:

```bash
curl -fsS http://campsites/healthz
curl -I http://gitea
ssh -p 2222 git@gitea
```

Expected result:

- `http://campsites/healthz` returns JSON with `status: ok`
- `http://gitea` returns the Gitea UI or setup page
- SSH reaches Gitea via `gitea`

From a phone on Wi-Fi:

```text
http://<server-ip>/campsites
http://<server-ip>:8096
```

In the Jellyfin mobile app, add the server manually as:

```text
http://<server-ip>:8096
```

Expected result:

- the sample Flask app loads through Caddy
- Jellyfin loads; if automated bootstrap was used, sign in with the configured admin user and confirm the default libraries are present
- the Jellyfin mobile app connects when given the full `http://` URL with port `8096`

If local DNS is configured, also test:

```text
http://campsites
```

## Gitea Clone Test

After Gitea first-run setup and SSH key configuration:

```bash
git clone ssh://git@<server-ip>:2222/<owner>/<repo>.git
```

Expected result:

- clone succeeds from the laptop
- pushing a small commit succeeds
- the commit is visible in the Gitea web UI

Port `2222` is intentional. It avoids fighting the host's normal SSH service on port `22`.

If local DNS exists, also test:

```bash
git clone ssh://git@gitea:2222/<owner>/<repo>.git
```

## Jellyfin Test

From a laptop browser:

```text
http://<server-ip>:8096
```

Expected result:

- Jellyfin UI loads
- the first-run wizard can create an admin user
- a test library can be created against `/media`

From a Jellyfin mobile or TV app on the same LAN:

- connect to `http://<server-ip>:8096`
- sign in with the Jellyfin admin or test user
- play a small test media file

This day-1 repo does not require public internet exposure for Jellyfin. Outside-the-home streaming should be treated as a separate networking/security decision.

## Power Loss Test

Unplug the server, wait 30 seconds, and plug it back in.

After the machine has had enough time to boot, test from a laptop first:

```bash
curl -fsS http://<server-ip>/campsites
curl -I http://<server-ip>
```

If local DNS exists, also test:

```bash
curl -fsS http://campsites/healthz
curl -I http://gitea
```

Then test from a phone on Wi-Fi:

```text
http://<server-ip>/campsites
```

Expected result:

- Docker starts on boot
- Caddy, Gitea, Jellyfin, and the sample app restart automatically
- routes work without SSHing into the server or manually starting anything

Optional server-side confirmation:

```bash
ssh <server-user>@<server-ip>
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
```

## Failure Reporting Standard

If any test fails, capture:

```bash
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/status.sh
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/logs.sh --no-log-prefix
ip addr
ip route
resolvectl status
```

The fix should be backported into this repo before the server is considered complete.
