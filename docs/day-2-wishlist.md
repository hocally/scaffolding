# Day 2 Wishlist

Day 1 is complete when the server can be rebuilt from fresh Ubuntu, services come up automatically, Gitea works from a laptop, Jellyfin works on the LAN, and the sample Flask app works from a phone.

Day 2 is the backlog after that baseline is real. These tasks should be chosen intentionally, not smuggled into day-1 commissioning.

## Recommended Next

### 1. Backups With A Restore Test

This is the highest-priority Day 2 task.

Goal:

- back up `/srv/data/gitea`
- back up `/srv/data/jellyfin/config`
- decide whether `/srv/media` is backed up, partially backed up, or treated as replaceable
- perform and document a restore test

Recommended approach: restic to an external disk or another trusted machine.

Alternative: rsync to an ext4 external disk. This is simpler to inspect but weaker on retention, deduplication, and encryption.

Done means:

- backup command is represented in the repo
- restore command is documented
- a restore test has been run
- docs do not imply backups exist before they really do

### 2. Remote Admin With Tailscale

Goal:

- SSH to the server without depending on home router port forwarding
- keep public internet exposure low

Recommended approach: install Tailscale for admin access only.

Alternative: WireGuard directly, but it usually requires more operator effort and router/network knowledge.

Done means:

- install steps are scripted or documented
- server appears in the tailnet
- SSH works over the Tailscale IP/name
- LAN service exposure remains unchanged unless intentionally expanded

### 3. Update And Rollback Procedure

Goal:

- keep image pins intentional
- make upgrades boring
- make rollback obvious

Done means:

- each service has a documented upgrade path
- `docker compose pull <service>` and `docker compose up -d <service>` flow is tested
- rollback means reverting the image pin and redeploying
- validation commands are run after upgrade and rollback

### 4. External Storage Plan

Goal:

- support media growth without turning the server into a snowflake

Recommended approach: ext4 external disk mounted by UUID under a documented mount point.

Alternative: keep everything internal until capacity pressure exists.

Done means:

- mount path is documented
- `/etc/fstab` entry is documented or scripted
- failure behavior is understood if the disk is missing at boot
- media paths in Jellyfin are updated intentionally

## Useful Soon

### Hardware Transcoding

Goal:

- allow Jellyfin to use the server's hardware video encoder when needed

Do this only after verifying:

```bash
ls -l /dev/dri
```

Done means:

- Compose maps the required device
- user/group permissions are correct
- Jellyfin actually performs a hardware transcode in a real playback test

### App Hosting Template

Goal:

- make adding future local apps boring and repeatable

Done means:

- a documented app skeleton exists
- persistent data goes under `/srv/data/apps/<app-name>`
- Caddy route pattern is clear
- validation includes the new route

### LAN DNS Service

Goal:

- make names such as `http://gitea` and `http://campsites` work consistently from laptops and phones

This is especially relevant on consumer mesh-router networks, where IP reservations may be available but arbitrary local DNS host overrides are not guaranteed.

Day 1 can use mDNS names such as `<server-hostname>.local` through Avahi. This Day 2 item is only for bare names such as `homeserver`, `gitea`, and `campsites`.

Recommended approach: add Pi-hole or AdGuard Home as a small LAN DNS service after day 1 is stable.

Done means:

- DNS service has a stable IP
- router hands it out as DNS or forwards DNS to it
- `gitea` and `campsites` resolve from laptop and phone
- server still works if DNS is temporarily degraded via the IP fallback route

### Lightweight Health Checks

Goal:

- catch obvious operational problems without a heavy monitoring stack

Useful checks:

- container health
- disk usage
- listening ports
- failed systemd units
- recent Compose logs

Done means:

- one command reports actionable status
- failures print the next command to run
- no heavyweight dashboard is required

## Security Hardening

Do after the happy path works:

- disable Gitea registration after first admin creation
- confirm only intended ports are open
- use SSH keys for server login
- consider disabling password SSH login
- consider Ubuntu unattended security updates for host packages
- keep container upgrades manual and pinned

## Defer Unless Needed

These are valid later, but should not become default day-2 work without a concrete reason:

- public internet exposure for local apps
- complex SSO
- Kubernetes, Nomad, Swarm, or k3s
- central secrets managers
- heavy monitoring stacks
- ZFS or btrfs
- high availability patterns

## Periodic Drills

Run occasionally:

```bash
COMPOSE_DIR=/srv/compose ./scripts/validate.sh
STRICT_DNS=1 COMPOSE_DIR=/srv/compose ./scripts/validate.sh
```

Then prove at least one recovery path:

- restore Gitea into a temporary directory
- rebuild from clean Ubuntu
- verify docs still match the real setup

If the drill requires an undocumented manual step, backport it into the repo.
