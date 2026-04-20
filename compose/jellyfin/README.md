# Jellyfin

Jellyfin is exposed directly on the LAN at:

```text
http://<server-ip>:8096
```

The recommended day-1 approach is direct LAN access rather than reverse proxying Jellyfin through Caddy. This avoids subpath/base-URL complexity and keeps media streaming behavior easy to reason about.

Alternative: reverse proxy Jellyfin through a dedicated hostname later, after local DNS is reliable.

## Mobile App Setup

On the same Wi-Fi/LAN, add the server manually in the Jellyfin mobile app:

```text
http://<server-ip>:8096
```

Use the full `http://` URL with port `8096`. Do not rely on automatic discovery during day-1 setup, and do not use `https://` unless Jellyfin is later placed behind a properly configured HTTPS reverse proxy.

On iPhone, allow Jellyfin local-network access if prompted. If the app cannot connect but the phone browser can load `http://<server-ip>:8096`, check `Settings -> Apps -> Jellyfin -> Local Network`.

## Automated Initial Setup

Recommended for rebuilds: automate the first-run wizard from `bootstrap/env`.

```text
JELLYFIN_BOOTSTRAP=1
JELLYFIN_ADMIN_USERNAME=<admin-user>
JELLYFIN_ADMIN_PASSWORD=<one-time-password>
JELLYFIN_SERVER_NAME=<server-name>
JELLYFIN_CREATE_DEFAULT_LIBRARIES=1
JELLYFIN_MOVIES_LIBRARY_PATH=/media/movies
JELLYFIN_TV_LIBRARY_PATH=/media/tv
JELLYFIN_MUSIC_LIBRARY_PATH=/media/music
```

When `JELLYFIN_BOOTSTRAP=1`, bootstrap completes the startup wizard, creates the admin user, optionally creates the default media libraries, then clears `JELLYFIN_ADMIN_PASSWORD` and sets `JELLYFIN_BOOTSTRAP=0` in `bootstrap/env`. Store the password in a password manager before running bootstrap.

The automation follows Jellyfin's public startup API: initial configuration, startup user, wizard completion, authentication, and virtual-folder creation. It intentionally does not configure remote access or UPnP.

## Manual Initial Setup

1. Open `http://<server-ip>:8096`.
2. Complete Jellyfin's first-run wizard.
3. Create the first admin user.
4. Add libraries using paths under `/media`.

Suggested library paths:

```text
/media/movies
/media/tv
/media/music
```

The host media directory is mounted read-only in the container. This prevents Jellyfin from accidentally modifying media files. If you later want Jellyfin to write metadata files beside media, change that mount intentionally and document the reason.

## State And Media

```text
/srv/data/jellyfin/config   Jellyfin configuration and database state
/srv/data/jellyfin/cache    Jellyfin cache and transcode scratch data
/srv/media                  Media library root, mounted read-only at /media
```

## Hardware Transcoding Later

This scaffold does not enable hardware transcoding by default because `/dev/dri` permissions vary by host.

When needed, verify the host exposes Intel graphics:

```bash
ls -l /dev/dri
```

Then add the appropriate device mapping and group access to `compose/docker-compose.yml`, backport the change to the repo, and validate with an actual transcode.
