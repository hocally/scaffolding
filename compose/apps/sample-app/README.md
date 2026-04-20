# Sample Local App

The sample app is a tiny Flask service routed by Caddy at:

```text
http://campsites
```

This demonstrates the intended local app pattern:

1. add a service or build context to `compose/docker-compose.yml`
2. keep it on the `backend` network
3. add a named route in `compose/caddy/Caddyfile`
4. add a local DNS record pointing the hostname to the server IP

For a real app, replace the `sample-app` image and command with the application container, then keep persistent state under `/srv/data/apps/<app-name>`.
