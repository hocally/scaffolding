# AGENTS.md

## Purpose

This repository defines a small, reproducible, low-overhead home server for a compact x86_64 or arm64 machine running Ubuntu Server 24.04 LTS.

The system is intended to feel like a cleanly managed small production system, not an ad hoc homelab snowflake. It must be straightforward to recreate from scratch on new hardware with minimal operator effort.

Primary day-1 services:
- Jellyfin
- Gitea
- local webapp hosting on the LAN

Secondary goals:
- clean local-network access patterns
- resilience to reboots, power blips, and transient network loss
- low ongoing maintenance burden
- easy future addition of backups, external storage, and Tailscale remote admin

## Operator Model

The operator is in "light operator mode".

That means:
- the operator is comfortable running commands over SSH
- the operator wants the system behavior to be boring and scripted
- the operator does not want to hand-manage drift
- the operator does not want heavyweight infrastructure platforms

Manual host changes are allowed in emergencies, but any such change must be backported into this repo immediately afterward.

## Priorities

When making design decisions, optimize in this order:

1. simplicity
2. reproducibility
3. resilience
4. elegance and clean repo structure
5. debuggability
6. security
7. speed of setup
8. minimal RAM/CPU usage

Prefer boring, widely used, operationally simple components unless there is a strong reason not to.

## Non-Goals

Do not introduce the following unless explicitly requested:
- Kubernetes
- Proxmox
- Nomad
- Swarm
- k3s
- NixOS
- heavy monitoring stacks
- service mesh
- complex centralized auth
- secrets managers with high operator overhead
- fancy filesystems without a clear need
- premature HA patterns

## Core Design Principles

### 1. Infrastructure as code
Everything reasonably possible must be represented in the repository:
- host bootstrap steps
- package installation
- service configuration
- container definitions
- reverse proxy configuration
- validation steps
- operational documentation

Avoid undocumented manual setup.

### 2. Rebuildability
A replacement machine should be able to reach a working baseline by:
- installing Ubuntu Server 24.04 LTS
- cloning this repo
- running one primary setup command/script
- supplying secrets or keys manually if needed

Design toward "reinstall Ubuntu, clone repo, run one script".

### 3. Minimize host complexity
Prefer:
- Ubuntu packages for a small host baseline
- Docker Engine + Docker Compose for service management
- a small amount of host scripting
- optional Ansible only if it materially improves reproducibility without adding significant operator burden

Do not add layers just because they are fashionable.

### 4. Prefer explicitness over cleverness
Use:
- pinned image versions
- explicit directory layout
- explicit bind mounts
- explicit service names
- explicit ports
- explicit health checks where useful
- explicit validation commands

Avoid hidden automation and magical abstractions.

### 5. Fail in understandable ways
Scripts and configs should prioritize:
- clear logging
- meaningful errors
- idempotent behavior where practical
- safe reruns
- easy debugging

## Technical Baseline

### Host OS
- Ubuntu Server 24.04 LTS

### Primary service runtime
- Docker Engine
- Docker Compose plugin

### Initial service choices
- Jellyfin for media serving
- Gitea for personal git hosting
- Caddy as reverse proxy for local webapps and Gitea
- plain HTTP on local DNS names for LAN access

### Network assumptions
- server primarily uses Ethernet
- server should be assigned a DHCP reservation or otherwise stable LAN IP
- local DNS integration should be designed so users on Wi-Fi can access services via simple LAN names such as `http://campsites`
- bare hostnames are acceptable if that is what the operator wants, even if a suffix-based domain would be more portable

### Storage assumptions
Use the boring, reliable option by default:
- ext4
- simple host directory layout under `/srv`
- no ZFS or btrfs unless explicitly requested later

Suggested host paths:
- `/srv/compose`
- `/srv/data`
- `/srv/data/gitea`
- `/srv/data/jellyfin`
- `/srv/data/apps`
- `/srv/media`
- `/srv/backups` (reserved for future use)

### Backup posture
Do not implement a complete backup system on day 1 unless requested, but design for easy future adoption.

Acceptable day-1 backup posture:
- structure directories cleanly
- isolate persistent state
- leave obvious mount points for future backup targets
- optionally scaffold restic-related directories or notes, but do not pretend backups exist if they do not

## Expected Repo Behavior

When making changes, always prefer:
- full-file outputs over diffs when generating files
- preserving established repo structure unless there is a compelling reason to change it
- comments for non-obvious decisions
- pinned versions
- README updates when infra changes
- rollback notes
- no hidden magic

Do not silently delete features or change architectural direction.

## Required Output Style

When generating or modifying repo content:
- provide full file contents unless asked otherwise
- explain major design decisions briefly and concretely
- state assumptions clearly
- include one recommended option and one alternative when requirements are ambiguous
- do not ask unnecessary clarifying questions if a safe, boring default exists

## Verification Expectations

Every meaningful infra change should include lightweight verification steps.

Prefer a compact validation section containing things like:
- exact commands to run
- `docker compose ps`
- `docker compose logs --tail`
- `systemctl status`
- `ss -tulpn`
- `curl` smoke tests
- simple reboot/power-cycle validation notes where relevant

Validation should be practical and fast, not ceremonial.

When the operator needs to test something manually, always provide a clear, concise command sequence that can be copied and run. Include where to run it, for example "on the server" or "on a laptop", and include the expected result in one or two bullets.

After a large or behaviorally important set of changes, explicitly ask for manual verification from the operator even if automated validation passed. Keep the request narrow: identify the exact URL, command, app screen, reboot check, or LAN-client behavior that still needs human confirmation.

## Security Expectations

Security matters, but operational simplicity matters too.

Defaults:
- expose only what is needed
- prefer reverse proxying for web apps
- keep internal services private unless there is a reason not to
- pin versions
- document update procedures
- avoid unnecessary internet exposure
- use SSH keys rather than passwords where possible

Do not add heavy auth or secret-management machinery on day 1.

## Update Policy

Assume:
- very stable pinned versions
- manual upgrades only
- changes should be conservative
- updates should be proposed with rationale
- critical security updates should be easy to apply intentionally

Do not quietly float to latest tags.

## Secrets Policy

Keep secrets dead simple for now.

Acceptable near-term patterns:
- `.env` files not committed
- manually provisioned SSH keys
- local secret files excluded via `.gitignore`

When handling secrets:
- never hardcode secrets in tracked files
- clearly document where secrets must be supplied
- keep the system easy to evolve later toward better secret management

### Operator config handoff

When a workflow needs the operator to fill values in an ignored local config file such as `bootstrap/env`, do as much of the file preparation as possible:

- add the exact keys and comments to the tracked example file
- add the same keys and comments to the ignored local file when it exists
- fill safe non-secret defaults or values already known from the repo/host
- leave only true secrets, private keys, or unknown operator-owned values blank
- tell the operator exactly which remaining blank values need to be filled

Do not make the operator manually copy a block of boilerplate when the file can be updated safely. For one-time bootstrap secrets, prefer an ignored local value that the script consumes and clears after successful setup.

## Preferred Structure

Unless there is a strong reason otherwise, prefer a repo structure roughly like:

```text
.
├── AGENTS.md
├── README.md
├── bootstrap/
│   ├── bootstrap.sh
│   ├── common.sh
│   └── env.example
├── compose/
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── caddy/
│   │   ├── Caddyfile
│   │   └── config/
│   ├── gitea/
│   │   └── app.ini.template
│   ├── plex/
│   │   └── README.md
│   └── apps/
│       └── sample-app/
├── scripts/
│   ├── validate.sh
│   ├── status.sh
│   ├── logs.sh
│   └── upgrade_notes.sh
├── docs/
│   ├── commissioning.md
│   ├── operations.md
│   ├── backup-plan.md
│   ├── network.md
│   └── recovery.md
└── .gitignore
