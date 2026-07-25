# Integrating a Container

This guide is the standard way to add a LAN-only application to this server. The intended result is a boring service: Docker restarts it after a reboot, its state has an obvious host location, Caddy is its only normal HTTP entry point, and the Mainframe dashboard makes it discoverable.

Use this guide for a regular HTTP application. Hardware access, host networking, public internet access, or a database shared by several applications need a separate design review before they are added.

## Design The Integration

Choose these values before editing files:

| Value | Example | Rule |
| --- | --- | --- |
| Compose service name | `example-app` | Lowercase, stable, and unique. It is the internal DNS name Caddy uses. |
| LAN path | `/example-app` | One short, unique path on `http://mainframe.local`. |
| Container port | `8080` | Keep it private to the Compose network unless a direct LAN port is required. |
| Persistent state | `/srv/data/apps/example-app` | All mutable application data lives below `/srv/data`. |
| Image | `ghcr.io/example/app:1.2.3@sha256:<digest>` | Pin external images to a version and digest; never use `latest`. |

Prefer an HTTP path under `mainframe.local` to a new local hostname. `mainframe.local` is supplied by mDNS, so it remains usable on the LAN without making the server a network-wide DNS dependency. A service that needs a native client port, such as Jellyfin or Gitea SSH, may expose that single port deliberately and should explain why in its service documentation.

## 1. Add The Service

Add a service to `compose/docker-compose.yml`. This is a representative template; replace image, port, health endpoint, environment, and mount target with the application's documented values.

```yaml
  example-app:
    image: ghcr.io/example/app:1.2.3@sha256:<64-character-image-digest>
    container_name: example-app
    restart: unless-stopped
    environment:
      TZ: ${TZ:-Etc/UTC}
    volumes:
      - /srv/data/apps/example-app:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://127.0.0.1:8080/healthz || exit 1"]
      interval: 1m
      timeout: 10s
      retries: 3
      start_period: 30s
```

Keep normal web applications on `backend` only. Do not add `ports:` just to make the service reachable: Caddy already joins `backend` and is responsible for LAN HTTP access. Add a `ports:` mapping only when a browser proxy cannot support the protocol or a client requires a direct port. Bind mounts should be narrow and read-only where possible; never mount the Docker socket or the whole host.

If the image is built by this repository, use a local image name with an explicit version, as `sample-app` does. If it is built elsewhere, document the build command and make the image a prerequisite, as the optional Retro Waveform service does.

Create the state directory on the server before first deployment so Docker does not create it as root unexpectedly:

```bash
sudo install -d -o "$(id -u)" -g "$(id -g)" /srv/data/apps/example-app
```

If the application needs a different owner, use its documented UID/GID instead and record that choice next to the service definition.

## 2. Add Configuration Safely

Put non-secret defaults and explanatory comments in `compose/.env.example`. Put real local values, especially passwords, API tokens, and private keys, only in the ignored `/srv/compose/.env`. Never commit those values.

For example:

```dotenv
# Public hostname or other non-secret default for example-app.
EXAMPLE_APP_BASE_URL=http://mainframe.local/example-app
# EXAMPLE_APP_API_TOKEN=   # Set only in /srv/compose/.env.
```

Reference the values from Compose with `${EXAMPLE_APP_BASE_URL:-...}` rather than hardcoding operator-specific settings. If the app generates its own secret on first start, store it within its `/srv/data/apps/example-app` directory.

## 3. Publish It Through Caddy

Add the route above the final fallback `handle` block in `compose/caddy/Caddyfile`:

```caddyfile
    @example_app path /example-app /example-app/*
    handle @example_app {
        uri strip_prefix /example-app
        reverse_proxy example-app:8080
    }
```

The matcher handles both the bare path and its descendants. `uri strip_prefix` is correct for applications that believe they are mounted at `/`. If the application must know its public base path, configure that application's base URL instead and test assets, redirects, webhooks, and login callbacks. Gitea is the reference case: it is configured with `GITEA_ROOT_URL` for `/gitea/` while Caddy strips the routing prefix.

Do not put the route after the fallback dashboard handler: the fallback would serve the dashboard instead. Do not use a new bare hostname unless there is a clear reason and a documented way clients resolve it.

Caddy's admin API is intentionally disabled. Therefore a changed Caddyfile takes effect only when Caddy is recreated; a plain file copy does not reload it.

## 4. Add It To The Dashboard

Add a card to `compose/caddy/site/index.html` using the Caddy path:

```html
<a href="/example-app">
  <strong>Example App</strong>
  <span>What this service is for.</span>
</a>
```

Keep the card name, route, Compose service name, and persistent-state directory consistent. If the service intentionally uses a direct port, use the dashboard's `data-service-port` pattern rather than hardcoding `mainframe.local`; this keeps the link correct if the dashboard is reached through another LAN hostname.

## 5. Document And Test It

Add a short service-specific README under `compose/<service>/` or `compose/apps/<service>/` that states:

- its purpose and image/build source;
- every persistent path and its expected ownership;
- its LAN URL and any deliberate direct ports;
- required operator-provided configuration and where it belongs;
- health check, update, and rollback commands;
- any security-relevant permissions or network exceptions.

Add an acceptance test to `docs/acceptance-tests.md` for the user-visible path. For a repository-owned integration, also extend `tests/static_repo_checks.sh` so the service, route, image-pinning rule, and documentation cannot be accidentally removed independently.

## 6. Validate And Deploy

From the repository checkout, run the normal checks before touching the host:

```bash
bash -n bootstrap/bootstrap.sh bootstrap/common.sh scripts/*.sh
./tests/static_repo_checks.sh
OFFLINE=1 COMPOSE_DIR=compose ./scripts/validate.sh
```

On the server, first ensure `/srv/compose` contains the reviewed repository version while preserving its ignored `.env`. Then deploy only the changed service and Caddy:

```bash
cd /srv/compose
sudo docker compose config
sudo docker compose up -d example-app
sudo docker compose up -d --no-deps --force-recreate caddy
sudo docker compose ps
sudo docker compose logs --tail 100 example-app caddy
curl -fsS http://mainframe.local/example-app/healthz
```

Use the application's actual health endpoint in the final command. A browser check from a different LAN device is still required: open `http://mainframe.local/example-app` and confirm the dashboard card, links, redirects, and static assets work. If the service uses a direct port, test that port from the same device too.

Avoid `docker compose down` for a one-service rollout: it interrupts unrelated services. A Compose service with `restart: unless-stopped` will return after Docker restarts following a power loss or normal reboot.

## Rollback

If the deployment fails, revert the service definition, Caddy route, dashboard card, environment example, and docs together. Sync the reverted Compose files to `/srv/compose`, then run:

```bash
cd /srv/compose
sudo docker compose up -d --no-deps --force-recreate caddy
sudo docker compose ps
sudo docker compose logs --tail 100 caddy
```

Stop the failed service explicitly only if it remains defined:

```bash
sudo docker compose stop example-app
```

Do not delete `/srv/data/apps/example-app` during an application rollback. Keep the data until the service is deliberately decommissioned and its retention or backup decision is documented.
