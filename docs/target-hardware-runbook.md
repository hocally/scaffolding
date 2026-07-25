# Target Hardware Runbook

This is the handoff for a first real server commissioning pass.

The purpose is not to lovingly configure one machine. The purpose is to prove this repo can produce a boring, rebuildable home server on fresh Ubuntu Server 24.04 LTS.

## Ground Rules

- Do not make manual host changes without writing them down.
- If a manual change is needed, backport it into this repo before calling the pass complete.
- Prefer fixing scripts and docs over relying on memory.
- Keep the target on Ethernet while commissioning.
- Do not expose services to the public internet during day-1 setup.

## Information To Collect First

On the server after Ubuntu install:

```bash
hostname -s
ip addr
ip route
resolvectl status
```

From the repo checkout:

```bash
./scripts/network-info.sh
```

Record:

- Ubuntu username
- server hostname
- Ethernet MAC address
- detected server IP
- router/gateway IP
- DNS server IP
- whether the router supports DHCP reservation
- whether the router supports local DNS records or host overrides
- Wi-Fi MAC address, if Wi-Fi is the primary connection

Router note: most consumer routers can create DHCP reservations, but arbitrary local DNS records are not guaranteed. Treat IP-based access as the day-1 fallback until DNS behavior is proven on the actual LAN.

## First Commissioning Pass

Install Ubuntu Server 24.04 LTS.

During install:

- use Ethernet
- create the normal operator user
- choose the hostname naturally; bootstrap detects it
- install OpenSSH Server if offered

After first boot:

```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y git
sudo reboot
```

Clone the repo:

```bash
git clone <repo-url> ~/scaffolding
cd ~/scaffolding
```

Run local static checks before changing the host:

```bash
./tests/static_repo_checks.sh
```

Create bootstrap config:

```bash
cp bootstrap/env.example bootstrap/env
$EDITOR bootstrap/env
```

Set `SERVER_USER` only if sudo-user detection would be ambiguous. Leave `SERVER_HOSTNAME` blank unless intentionally overriding the Ubuntu hostname.

If you want mDNS for the LAN, set:

```text
SERVER_HOSTNAME=<server-hostname>
ENABLE_MDNS=1
```

That should make the server reachable as `<server-hostname>.local` on clients that support mDNS. Do not expect a bare hostname to work without real DNS.

For a laptop-style server, leave `DISABLE_LID_SLEEP=1`. Before relying on unattended recovery, set its firmware/BIOS `Restore on AC Power Loss` (or similarly named) option to `Power On` or `Last State`; this setting cannot be applied by Ubuntu.

Leave `GITEA_ACCESS_HOST` blank unless local DNS already works. Blank means bootstrap will make Gitea advertise the detected LAN IP, which is the most reliable day-1 default.

For a cleaner rebuild, fill the optional Gitea and Jellyfin bootstrap sections in `bootstrap/env` before running bootstrap. Both are one-time helpers: on success, bootstrap clears the admin password fields and flips the bootstrap flags back to `0`.

Bootstrap:

```bash
sudo ./bootstrap/bootstrap.sh
```

If Docker group membership changed, log out and back in.

## Router Work

Use the server IP and MAC reported by `scripts/network-info.sh` or the router UI.

Recommended:

```text
DHCP reservation:
  <active-network-mac> -> <server-ip>

Local DNS:
  gitea     -> <server-ip>
  campsites -> <server-ip>
```

For consumer routers, the reservation setting is usually somewhere like:

```text
Router admin UI or mobile app -> DHCP reservation
```

Add the server as an IPv4 reservation after it appears as a connected device. Do not assume the router can add `gitea` or `campsites` as custom local DNS records.

If bare names do not work reliably, switch to `home.arpa` names before going further:

```text
gitea.home.arpa
campsites.home.arpa
```

Then update:

- `/srv/compose/.env`
- `/srv/compose/caddy/Caddyfile`
- repo copies of those files
- docs that mention the names

Do not leave this as an undocumented local workaround.

It is acceptable for day 1 if the IP-based fallback works:

```text
http://<server-ip>/campsites
```

Bare names can become a Day 2 DNS task if the router does not provide host overrides.

## Server-Side Validation

Run:

```bash
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/status.sh
```

Run strict DNS only after local DNS records are actually configured:

```bash
STRICT_DNS=1 COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
```

Expected:

- Compose config renders
- Docker daemon is reachable
- Caddy is running
- Gitea responds through Caddy at the server IP
- Flask sample app responds through Caddy
- Jellyfin public system info endpoint responds
- mDNS works as `<server-hostname>.local` if `ENABLE_MDNS=1`
- strict DNS passes only if router/local-DNS records are available
- host package versions are recorded at `/srv/compose/host-package-versions.txt`
- Docker is enabled and starts after `network-online.target`

If this fails, capture:

```bash
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/status.sh
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/logs.sh
ip addr
ip route
resolvectl status
```

Then fix the repo, rerun bootstrap or resync `/srv/compose`, and validate again.

## Client-Side Validation

From a laptop on the LAN:

```bash
./scripts/network-info.sh
curl -fsS http://<server-ip>/campsites
curl -I http://<server-ip>
```

Expected:

- Flask sample app responds through the IP fallback
- Caddy responds on the server IP

If DNS names resolve, also run:

```bash
curl -fsS http://campsites/healthz
curl -I http://gitea
ssh -p 2222 git@gitea
```

Expected:

- Flask health endpoint returns JSON
- Gitea UI responds
- SSH reaches Gitea, even if auth fails before keys are configured

From a phone on Wi-Fi:

```text
http://<server-ip>/campsites
```

Expected:

- the Flask page loads

If DNS is configured and working, also test:

```text
http://campsites
```

## Gitea Completion

Open:

```text
http://<server-ip>
```

If local DNS is configured, `http://gitea` should work too.

Complete first-run setup and create the first admin user.

Then lock down registration:

```bash
sudoedit /srv/compose/.env
cd /srv/compose
sudo docker compose up -d gitea
```

Set:

```text
GITEA_DISABLE_REGISTRATION=true
```

Add an SSH key to the Gitea user, create a test repo, then from a laptop on the LAN:

```bash
git clone ssh://git@<server-ip>:2222/<owner>/<repo>.git
cd <repo>
date > smoke.txt
git add smoke.txt
git commit -m "smoke test"
git push
```

Expected:

- clone succeeds
- push succeeds
- commit appears in Gitea web UI

If local DNS is configured, repeat the clone test with `ssh://git@gitea:2222/<owner>/<repo>.git`.

## Jellyfin Completion

Open:

```text
http://<server-ip>:8096
```

Complete the first-run wizard and create the first admin user.

Add a small test library under:

```text
/media
```

From a Jellyfin app on the same LAN:

- connect to `http://<server-ip>:8096`
- sign in with the Jellyfin admin or test user
- confirm the server appears
- play a small test file

Do not require outside-the-home streaming for the day-1 acceptance test. If outside access is desired later, decide intentionally between reverse proxying, router port forwarding, and Tailscale.

## Power-Loss Test

Unplug the server. Wait 30 seconds. Plug it back in.

After boot:

```bash
ssh <server-user>@<server-ip>
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
```

From a laptop on the LAN:

```bash
curl -fsS http://<server-ip>/campsites
curl -I http://<server-ip>
```

If local DNS exists, also run:

```bash
STRICT_DNS=1 COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
curl -fsS http://campsites/healthz
curl -I http://gitea
```

Expected:

- Docker starts automatically
- all containers restart automatically
- routes recover without manual action

## Wipe/Rebuild Proof

Only after the first pass is fixed and committed:

1. Push the repo to GitHub.
2. Wipe the server.
3. Reinstall Ubuntu Server 24.04 LTS.
4. Clone the repo.
5. Run the same bootstrap command.
6. Repeat all acceptance tests.

The rebuild pass is successful only if no undocumented manual fix is needed.

## Likely Things Future You May Need To Fix

- Router does DHCP reservation but not local DNS. Decide whether to use `home.arpa`, Pi-hole/AdGuard later, or document router-specific limitations.
- Bare names work on laptop but not phone. Prefer suffix names or proper local DNS rather than hosts files.
- Gitea first-run settings disagree with env-driven settings. Backport exact settings into Compose/env docs.
- Jellyfin first-run behavior differs depending on prior config state. Document the exact path that worked.
- Hardware transcoding needs `/dev/dri` mapping. Add it only after verifying the server exposes compatible graphics hardware and Jellyfin actually uses it.
- Ubuntu Server image does not include a package assumed by scripts. Add it to bootstrap and rerun from clean install.
