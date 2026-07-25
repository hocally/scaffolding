# Commissioning

These steps are for the actual Ubuntu Server 24.04 LTS machine.

## Assumptions

- Ubuntu Server 24.04 LTS is installed.
- The server uses Ethernet.
- The operator account can use `sudo`.
- The server has a stable LAN IP, preferably via DHCP reservation.
- Local DNS may map `gitea` and `campsites` to the server IP, but the day-1 flow also works with IP-based fallback URLs.

Recommended network approach: configure a DHCP reservation on the router and add local DNS records if the router supports them. Alternative: use the server IP for day 1 and add LAN DNS later.

The bootstrap script detects the hostname set during Ubuntu installation. You do not need to duplicate that in this repo unless you want to override it in `bootstrap/env`.

If you want an mDNS name such as `<server-hostname>.local`, set `SERVER_HOSTNAME=<server-hostname>` and `ENABLE_MDNS=1` in `bootstrap/env` before running bootstrap.

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

By default, bootstrap sets Gitea's advertised HTTP and SSH host to the detected LAN IP. If local DNS is already working and you prefer a name, set `GITEA_ACCESS_HOST` in `bootstrap/env` before bootstrap or edit `/srv/compose/.env` afterward.

If `GITEA_BOOTSTRAP=1` or `JELLYFIN_BOOTSTRAP=1`, bootstrap performs those first-run setup steps after the Compose stack starts. On success, it clears the corresponding one-time identity/password fields in `bootstrap/env` and disables that bootstrap flag so reruns are safe.

If mDNS is enabled, `http://<server-hostname>.local`, `http://<server-hostname>.local/campsites`, and `http://<server-hostname>.local:8096` should work on clients that support mDNS.

9. Add a DHCP reservation in the router for the detected server IP.

10. If the router supports local DNS records, add:

```text
gitea      -> <server-ip>
campsites  -> <server-ip>
```

11. Validate:

```bash
COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
systemd-analyze cat-config systemd/logind.conf | grep -E '^[[:space:]]*HandleLidSwitch(ExternalPower|Docked)?='
```

Only run strict DNS validation after local DNS records exist:

```bash
STRICT_DNS=1 COMPOSE_DIR=/srv/compose ~/scaffolding/scripts/validate.sh
```

12. Run the acceptance tests in `docs/acceptance-tests.md`.

For the lid policy check, the expected result is that all three `HandleLidSwitch` values are `ignore`. After bootstrap, close the lid for a minute from another LAN client and confirm SSH still responds.

## First Gitea Login

Open `http://<server-ip>` or `http://gitea`, complete the first-run setup, and create the first user. Then disable open registration:

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
