# Network

The default design uses plain HTTP on LAN-only names:

```text
http://gitea
http://campsites
```

Bare names are ergonomic when the router or local DNS server supports them. They are not guaranteed by the server alone; clients need DNS to turn `gitea` and `campsites` into the server IP.

## Recommended DNS Setup

Use the router or local DNS server to create records:

```text
gitea      A  <server-ip>
campsites  A  <server-ip>
```

Also configure a DHCP reservation so the server keeps the same IP.

DHCP reservation means the router always gives the server the same IP address based on the server's network adapter MAC address. This is usually safer than setting a static IP on the server because the router still owns the subnet, gateway, DNS, and conflict avoidance.

Local DNS means the router answers LAN-only names. Some routers call this "local DNS", "host overrides", "DNS records", "address reservation hostname", or "LAN DNS". The required behavior is simple: a phone or laptop on Wi-Fi should resolve `campsites` to the server IP.

## Consumer Router Notes

Consumer routers vary widely in local DNS behavior. Most can create DHCP reservations, but some cannot create arbitrary LAN DNS records such as `gitea -> <server-ip>` or `campsites -> <server-ip>`.

Use the router's admin UI or mobile app to create an IPv4 reservation for the server after it appears as a connected device. Router vendors commonly place this under a section with a name similar to:

```text
Advanced networking -> Reservations
LAN -> DHCP reservation
Network -> Clients -> Reserve IP
```

Treat bare hostnames as nice-to-have until proven on the actual network. The day-1 fallback URL is:

```text
http://<server-ip>/campsites
```

If bare names are required on phones, plan on adding a real LAN DNS service later, such as Pi-hole or AdGuard Home, and pointing router custom DNS at it.

## LAN Hostname Notes

If a server is reachable by IP but not by a short hostname such as `home`, the problem is name resolution, not routing.

Some routers expose client nicknames in their app but do not publish those names through DNS. Do not treat router UI nicknames as reliable LAN DNS records until tested from a client.

Recommended local setup:

1. Reserve the server IP in the router:

```text
Router admin UI or mobile app -> DHCP reservation
```

2. Use mDNS for a low-overhead hostname:

```text
<server-hostname>.local
```

To make this repo configure mDNS during bootstrap, set these values in `bootstrap/env` before running bootstrap:

```text
SERVER_HOSTNAME=<server-hostname>
ENABLE_MDNS=1
```

The bootstrap script will set the system hostname if needed, install `avahi-daemon`, and enable it.

3. Access the server from laptops and phones that support mDNS:

```text
http://<server-hostname>.local
http://<server-hostname>.local/campsites
http://<server-hostname>.local:8096
```

Bare hostnames require real DNS. If that is important, run a local DNS server such as Pi-hole or dnsmasq, add a record such as `homeserver -> <server-ip>` there, and set the router's custom DNS to that server.

Router security, smart-home, or local DNS caching features may route DNS through the gateway or prevent direct custom DNS behavior, so prefer mDNS unless bare hostnames are worth the extra DNS service.

Run this from a laptop to see the current client-side network shape:

```bash
./scripts/network-info.sh
```

Run it on the server after Ubuntu install to capture the server IP, gateway, and suggested records:

```bash
~/scaffolding/scripts/network-info.sh
```

## Alternative DNS Setup

If bare hostnames are unreliable on your clients, use a suffix such as `home.arpa`:

```text
gitea.home.arpa
campsites.home.arpa
```

If you do that, update both:

- `/srv/compose/.env`
- `/srv/compose/caddy/Caddyfile`

Then restart Caddy and Gitea:

```bash
cd /srv/compose
sudo docker compose up -d caddy gitea
```

If the router cannot create local DNS records, practical alternatives are:

- run a small LAN DNS service such as Pi-hole or AdGuard Home later
- use per-client hosts files for laptops only
- use the fallback sample-app path `http://<server-ip>/campsites`

Per-client hosts files do not help most phones and are not recommended as the normal operating model.

## Exposed Ports

| Port | Service | Reason |
| --- | --- | --- |
| `80/tcp` | Caddy | LAN HTTP for Gitea and local apps |
| `2222/tcp` | Gitea SSH | Git over SSH |
| `8096/tcp` | Jellyfin | Jellyfin web UI and clients |
| `7359/udp` | Jellyfin | LAN discovery for Jellyfin clients |

Jellyfin is exposed directly on the LAN. DLNA-related ports are not exposed by default; add them later only if DLNA is intentionally enabled.

## Smoke Tests

From a LAN client:

```bash
curl -I http://<server-ip>
curl -fsS http://<server-ip>/campsites
```

If local DNS exists, also test:

```bash
curl -I http://gitea
curl -I http://campsites
curl -fsS http://campsites/healthz
ssh -p 2222 git@gitea
```

The SSH command may fail authentication before keys are configured; that still proves the port is reachable.

## Wi-Fi Reconnection and Diagnostics

Wi-Fi credentials and interface names are intentionally not stored in this repository: they are host-specific secrets managed by Ubuntu Netplan. Once the host has joined the new Wi-Fi network, create a DHCP reservation for its Wi-Fi MAC address, not an old Ethernet MAC address.

Bootstrap installs the small diagnostic set used for troubleshooting: `iproute2`, `iw`, `ethtool`, `iputils-ping`, `dnsutils`, `mtr-tiny`, and `traceroute`. Docker's packaged systemd unit starts after `network-online.target`, and bootstrap ensures Docker is enabled; the existing Compose restart policies then restore the services after a normal reboot or Wi-Fi reconnection.

Run these commands on the server after joining the network and again after a reboot:

```bash
ip -br link
ip -4 route
iw dev
resolvectl status
ping -c 3 <router-ip>
dig +short gitea
systemctl is-enabled docker
systemctl is-active docker
```

Expected: the Wi-Fi interface has the reserved address, a default route and DNS servers are present, and Docker is `enabled` and `active`. Use `mtr -rw <router-ip>` or `traceroute <router-ip>` only when diagnosing an actual reachability problem.
