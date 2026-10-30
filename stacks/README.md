# Container stacks

Each `stacks/<name>/default.nix` is a NixOS module for one or more containers.

## Add a stack

1. Define `virtualisation.oci-containers.containers` in its `default.nix`.
2. Prefix container and volume names with the stack name.
3. Join frontends to `networks = [ "proxy" ];`; keep databases on private networks.
4. Import the stack in `hosts/<host>/default.nix`.
5. Add [encrypted secrets](../secrets.md), then commit and push to `main`.

`modules/nixos/containers.nix` supplies rootless defaults and the shared `proxy`
network. Images and volumes live on `/srv`; removing a stack preserves its volumes.

## Caddy

| File | Purpose |
| --- | --- |
| `caddy/config/Caddyfile` | Main configuration |
| `caddy/config/sites/*.caddy` | Automatically imported sites |
| `caddy/secrets.yaml` | Encrypted Cloudflare credential |

GitOps validates configuration and restarts Caddy for config or credential changes.
Volumes `caddy-data` and `caddy-config` persist certificates, logs and state.
Ports: TCP 80/443, UDP 443; rootless port threshold: 80.
Existing container-name upstreams become reachable as their stacks migrate to `proxy`.

Manage as root; run Podman commands as `containers`:

```sh
systemctl status podman-caddy.service
journalctl -u podman-caddy.service -n 30 --no-pager
```

### Caddy updates

The `Caddy updates` GitHub Actions workflow runs Mondays at 06:17 UTC and can
also be started manually. It refreshes the locked Nixpkgs revision on the current
NixOS branch, selects the latest stable Cloudflare plugin tag, and recalculates
and verifies the dependency hash. It builds the image and validates the Caddy
configuration before opening or refreshing one PR on `codex/update-caddy`.

Review and merge that PR to deploy through GitOps. Nixpkgs updates can also
change other host packages. The managed branch gets explicitly dispatched build
checks using GitHub's built-in token; no personal token or SOPS keys are needed.
Failures leave `main` unchanged and appear as failed workflow runs. The updater
restores its input files if dependency discovery or hash verification fails.

To refresh inputs locally on Linux, run `python3 scripts/update-caddy.py` with
Nix and authenticated `gh` available, then build `.#caddy-image` and
`.#checks.x86_64-linux.caddy-config` before committing the proposed update.

## DDNS Updater

Edit records in `ddns-updater/config.nix`, then commit and push to `main`.
GitOps generates fresh configuration and recreates `ddns-updater` whenever an
entry is added, removed, or changed. Credential changes also restart it.

The Cloudflare token is encrypted in `ddns-updater/secrets.yaml`. Configuration
is passed through a SOPS-rendered `CONFIG` environment variable; the persistent
`ddns-updater-data` volume holds update history, not the managed configuration.
The existing Caddy route serves `https://ddns.lesicnik.eu` over `proxy`.
Timezone `Europe/Ljubljana` and upstream DNS `8.8.8.8` match the Compose stack.
The image is pinned to `2.10.0`; change its version in `ddns-updater/default.nix`
and push to `main` to deploy an image update.

```sh
systemctl status podman-ddns-updater.service
journalctl -u podman-ddns-updater.service -n 30 --no-pager
```

## Immich Kiosk

`kiosk/config.nix` holds the Immich URL, album, display duration, locale and
screensaver settings. Commit and push changes to `main`; GitOps recreates the
container with the new settings. The Immich API key is encrypted in
`kiosk/secrets.yaml`, and credential changes also restart the container.

The image is pinned to `0.45.2`. Volume `kiosk-config` persists `/config`.
Caddy serves `https://kiosk.lesicnik.eu` through `immich-kiosk:3000` on `proxy`.

```sh
systemctl status podman-immich-kiosk.service
journalctl -u podman-immich-kiosk.service -n 30 --no-pager
```

## Beszel

The hub image is pinned to `0.21.1` in `beszel/default.nix`. Volume `beszel-data`
persists `/beszel_data`. This migration starts with a fresh database: create an
account and reconnect agents after switching the Caddy route. Old accounts,
systems, credentials and history are not imported.

Caddy serves `https://beszel.lesicnik.eu` through `beszel:8090` on `proxy`.
The public URL and OAuth user-creation setting match the Compose stack.

```sh
systemctl status podman-beszel.service
journalctl -u podman-beszel.service -n 30 --no-pager
```

## Dockhand

The image is pinned to `v1.0.55`. Caddy serves `https://docker.lesicnik.eu`.
On first installation, the service creates a `NixOS Podman` environment with
metrics and activity collection enabled. The rootless user's Podman socket is
mounted at `/var/run/docker.sock`; the rootful API stays disabled.

Volume `dockhand-data` persists its database and preferences on the data disk.
The socket starts before Dockhand, and the initial environment setup runs only
once, preserving later authentication and UI changes. Enable authentication
under Settings.

Use Dockhand as an overview of Nix-controlled containers: status, resource use,
logs, inspection, images, volumes and networks. Nix-managed containers carry
`NixOS` tags and labels disabling Dockhand updates and stack adoption. Manage
service definitions, lifecycle and image versions through Nix and GitOps.

```sh
systemctl status podman-dockhand.service
journalctl -u podman-dockhand.service -n 30 --no-pager
```

## Litara

Litara and PostgreSQL 16 are pinned to the exact image digests from the NAS.
The application joins `proxy` and the private `litara` network; PostgreSQL joins
only the private network, with no published database port. The original database
URL, password and JWT secret are encrypted in `litara/secrets.yaml`.

The complete library is at `/srv/litara/books`, mounted at the original `/books`
path. Volume `litara-postgres-data` holds the restored database, including users,
settings, metadata, reading progress and history. Caddy serves
`https://books.lesicnik.eu`; Dockhand displays both containers as Nix-managed.

Startup waits for PostgreSQL readiness. The application also requires
`/srv/litara/.migration-complete`, created only after the database restore and
file verification. Preserve that marker with the library when restoring a host;
do not create it over an empty database or missing library. Migration backups
are retained under `/srv/litara/migration-20261030` with restricted permissions.

```sh
systemctl status podman-litara.service podman-litara-postgres.service
journalctl -u podman-litara.service -n 30 --no-pager
```

## SABnzbd

The image is pinned to the original NAS digest (SABnzbd 5.1.3). The complete
configuration, API keys, history and queue state live at `/srv/sabnzbd/config`.
The NAS media share remains at `/mnt/media`, mounted at the original `/media`
container path, preserving incomplete downloads, completed files and categories.
UID/GID `1000` maps directly to the NAS identity through Podman's `keep-id` mode.

Caddy serves `https://usenet.lesicnik.eu` through `sabnzbd:8080` on `proxy`.
Startup requires the NFS mount and `/srv/sabnzbd/.migration-complete`; preserve
that marker with a verified configuration restore. A complete configuration
archive and checksum manifests are retained in `/srv/sabnzbd/migration-20261030`
with restricted permissions. The stopped NAS container and original volume are
retained for rollback. Sonarr and Radarr settings remain unchanged.

```sh
systemctl status podman-sabnzbd.service
journalctl -u podman-sabnzbd.service -n 30 --no-pager
```
