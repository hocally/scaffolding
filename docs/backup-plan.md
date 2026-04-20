# Backup Plan

Backups are not implemented on day 1.

This is intentional. The repository creates a layout that makes future backups straightforward, but it does not claim data is protected until a real backup job is configured, run, and restored in a test.

## Data To Protect

Highest priority:

```text
/srv/data/gitea
/srv/data/jellyfin/config
```

Large or replaceable depending on your media source:

```text
/srv/media
```

Reserved future target or staging path:

```text
/srv/backups
```

## Recommended Future Approach

Use restic to back up `/srv/data` and selected `/srv/media` paths to an external disk or another machine.

Alternative: use rsync to a directly attached ext4 disk. This is simpler to inspect but gives weaker deduplication, retention, and encryption behavior than restic.

## Restore Test Requirement

Before calling backups complete, perform a restore test onto a temporary directory and verify:

```bash
ls -la restored/srv/data/gitea
ls -la restored/srv/data/jellyfin/config
```

For Gitea, a real restore test should start a disposable Gitea container against the restored data.
