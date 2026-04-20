# Gitea

Gitea is exposed through Caddy at `http://<server-ip>` by default and at `http://gitea` when local DNS exists. Git SSH is exposed on host port `2222`.

The recommended day-1 database is SQLite. For a small personal Git host, this keeps backup and recovery simple because all state is under `/srv/data/gitea`. Alternative: PostgreSQL can be added later if repository size, concurrency, or operational needs justify the extra moving part.

## Initial Setup

Recommended for rebuilds: automate the first-run setup from `bootstrap/env`.

```text
GITEA_BOOTSTRAP=1
GITEA_ADMIN_USERNAME=<admin-user>
GITEA_ADMIN_EMAIL=<admin-email>
GITEA_ADMIN_PASSWORD=<one-time-password>
GITEA_ADMIN_SSH_PUBLIC_KEY_FILE=/home/<server-user>/.ssh/id_ed25519.pub
GITEA_BOOTSTRAP_REPO=init
```

When `GITEA_BOOTSTRAP=1`, bootstrap preconfigures Gitea, creates the admin user, disables registration, optionally adds the SSH key, optionally creates the first repo, then clears `GITEA_ADMIN_EMAIL` and `GITEA_ADMIN_PASSWORD` and sets `GITEA_BOOTSTRAP=0` in `bootstrap/env`. Store the email and password in a password manager before running bootstrap if you need to keep a record.

Manual fallback:

1. Open `http://<server-ip>`.
2. If local DNS exists, also confirm `http://gitea` works.
3. Complete Gitea's first-run setup.
4. Create the first user; it becomes the initial admin.
5. Edit `/srv/compose/.env` and set:

```text
GITEA_DISABLE_REGISTRATION=true
```

6. Restart Gitea:

```bash
cd /srv/compose
sudo docker compose up -d gitea
```

## SSH Clone URL

With the default settings, SSH clone URLs should use port `2222`:

```bash
git clone ssh://git@<server-ip>:2222/<owner>/<repo>.git
```

If local DNS exists, `ssh://git@gitea:2222/<owner>/<repo>.git` should work too.

## State

Persistent state lives in:

```text
/srv/data/gitea
```

Do not delete that directory unless you intentionally want to remove all Gitea data.
