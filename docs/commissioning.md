# Commissioning

These steps are for the actual Ubuntu Server 24.04 LTS machine.

## Assumptions

- Ubuntu Server 24.04 LTS is installed.
- The server uses Ethernet.
- The operator account can use `sudo`.
- The server has a stable LAN IP, preferably via DHCP reservation.
- mDNS makes the server available as `mainframe.local`; the day-1 flow also works with IP-based fallback URLs.

Recommended network approach: configure a DHCP reservation on the router and set `SERVER_HOSTNAME=mainframe` with `ENABLE_MDNS=1`. This gives LAN clients `mainframe.local` without making the server a network-wide DNS dependency. Alternative: use the server IP for day 1 and add LAN DNS later.

The bootstrap script detects the hostname set during Ubuntu installation. You do not need to duplicate that in this repo unless you want to override it in `bootstrap/env`.

For the standard Mainframe layout, set the following in `bootstrap/env` before running bootstrap:

```text
SERVER_HOSTNAME=mainframe
ENABLE_MDNS=1
```

By default, bootstrap sets `DISABLE_LID_SLEEP=1`, which makes systemd-logind ignore laptop lid-close events. Recommended: keep this for a home server that may run closed. Alternative: set `DISABLE_LID_SLEEP=0` before bootstrap if you want the machine to suspend when the lid closes.

## Steps

1. Install Ubuntu Server 24.04 LTS.
2. Apply OS updates:

```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y git
sudo reboot
```

3. Clone this repo:

```bash
git clone <this-repo-url> ~/scaffolding
cd ~/scaffolding
```

4. Inspect the network information the router will need:

```bash
./scripts/network-info.sh
```

5. Create bootstrap config:

```bash
cp bootstrap/env.example bootstrap/env
$EDITOR bootstrap/env
```

6. Run bootstrap:

```bash
sudo ./bootstrap/bootstrap.sh
```

7. If the script added your user to the `docker` group, log out and back in.

8. Review runtime configuration:

```bash
sudoedit /srv/compose/.env
```

With `ENABLE_MDNS=1`, bootstrap sets Gitea's advertised URL to `http://mainframe.local/gitea/` and its SSH host to `mainframe.local`. Without mDNS, it uses the detected LAN IP at `/gitea/`. Set `GITEA_ACCESS_HOST` only when using a different LAN name that already resolves.

If `GITEA_BOOTSTRAP=1` or `JELLYFIN_BOOTSTRAP=1`, bootstrap performs those first-run setup steps after the Compose stack starts. On success, it clears the corresponding one-time identity/password fields in `bootstrap/env` and disables that bootstrap flag so reruns are safe.

If mDNS is enabled, `http://mainframe.local`, `http://mainframe.local/gitea/`, `http://mainframe.local/campsites`, and `http://mainframe.local:8096` should work on clients that support mDNS.

9. Add a DHCP reservation in the router for the detected server IP.

10. Validate:

```bash
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
systemd-analyze cat-config systemd/logind.conf | grep -E '^[[:space:]]*HandleLidSwitch(ExternalPower|Docked)?='
```

Run the strict DNS validation only after deliberately configuring router-provided local DNS records; it is not needed for `mainframe.local` mDNS.

11. Run the acceptance tests in `docs/acceptance-tests.md`.

For the lid policy check, the expected result is that all three `HandleLidSwitch` values are `ignore`. After bootstrap, close the lid for a minute from another LAN client and confirm SSH still responds.

## First Gitea Login

Open `http://mainframe.local/gitea/` (or `http://<server-ip>/gitea/` if mDNS is disabled), complete the first-run setup, and create the first user. Then disable open registration:

```bash
sudoedit /srv/compose/.env
cd /srv/compose
sudo docker compose up -d gitea
```

Set:

```text
GITEA_DISABLE_REGISTRATION=true
```

## First Jellyfin Login

Open:

```text
http://<server-ip>:8096
```

Complete Jellyfin's first-run wizard, create the first admin user, and add media libraries under `/media`.

For day 1, "remote" means Jellyfin apps on the same LAN can connect to `http://<server-ip>:8096`. Outside-the-home streaming is a separate networking decision and is not required by this baseline.

## Rollback

Stop services without deleting data:

```bash
cd /srv/compose
sudo docker compose down
```

Remove only the copied Compose bundle:

```bash
sudo rm -rf /srv/compose
```

Persistent data remains in `/srv/data` and media remains in `/srv/media`.
