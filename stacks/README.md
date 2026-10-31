# Container stacks

Each `stacks/<name>/default.nix` is a NixOS module for one or more containers.

## Add a stack

1. Add a `Dockerfile` containing one `FROM registry/image:version` line. For
   additional containers in the same stack, use names such as `postgres.Dockerfile`.
2. Define `virtualisation.oci-containers.containers` in its `default.nix`, using
   `imageManifest = ./Dockerfile;` instead of a literal `image`.
3. Prefix container and volume names with the stack name.
4. Join frontends to `networks = [ "proxy" ];`; keep databases on private networks.
5. Import the stack in `hosts/<host>/default.nix`.
6. Add [encrypted secrets](../secrets.md), then commit and push to `main`.

`modules/nixos/containers.nix` supplies rootless defaults and the shared `proxy`
network. Images and volumes live on `/srv`; removing a stack preserves its volumes.

## Container image updates

Dependabot checks every `Dockerfile` under `stacks/` on Mondays at 08:00
Europe/Ljubljana and opens update PRs. New stacks are discovered automatically.
Nix reads the image directly from the single `FROM` line; these files are image
declarations and do not introduce another build. Keep them to that one line.
External containers must use `imageManifest`; host evaluation rejects omissions.

Review and merge PRs to deploy through GitOps. PostgreSQL stays on major version
16; a major upgrade requires a separate database migration. Use specific version
tags for external images so PRs show version changes instead of digest changes.
Caddy is built locally and retains its dedicated updater below. CI evaluates the
host on every PR. It builds and validates Caddy only when its files, dedicated input,
updater, or CI workflows change, or when manually dispatched. Application startup
and database compatibility still need runtime checks.

## Caddy

| File | Purpose |
| --- | --- |
| `caddy/config/Caddyfile` | Main configuration |
| `caddy/config/sites/*.caddy` | Automatically imported sites |
| `caddy/secrets.yaml` | Encrypted Cloudflare credential |

GitOps validates configuration and restarts Caddy for config or credential changes.
Volumes `caddy-data` and `caddy-config` persist certificates, logs and state.
Ports: TCP 80/443, UDP 443; rootless port threshold: 53 with AdGuard enabled.
Existing container-name upstreams become reachable as their stacks migrate to `proxy`.

Manage as root; run Podman commands as `containers`:

```sh
systemctl status podman-caddy.service
journalctl -u podman-caddy.service -n 30 --no-pager
```

### Caddy updates

The `Caddy updates` GitHub Actions workflow runs Mondays at 06:17 UTC and can
also be started manually. It refreshes the dedicated `caddy-nixpkgs` input on the current
NixOS branch, selects the latest stable Cloudflare plugin tag, and recalculates
and verifies the dependency hash. It builds the image and validates the Caddy
configuration before opening or refreshing one PR on `codex/update-caddy`.

The binary, image dependencies and configuration validator all use this separate
pin. Host package updates do not change Caddy. Review and merge that PR to deploy
through GitOps. The managed branch gets explicitly dispatched build
checks using GitHub's built-in token; no personal token or SOPS keys are needed.
Failures leave `main` unchanged and appear as failed workflow runs. The updater
restores its input files if dependency discovery or hash verification fails.

To refresh inputs locally on Linux, run `python3 scripts/update-caddy.py` with
Nix and authenticated `gh` available, then build `.#caddy-image` and
`.#checks.x86_64-linux.caddy-config` before committing the proposed update.

## HA Tablet

Caddy serves `https://tablet.lesicnik.eu` through `ha-tablet:80` on `proxy`.
The existing runtime `config.json`, including its Home Assistant connection,
is preserved in `ha-tablet/secrets.yaml` and mounted read-only. Secret changes
restart the service; application state does not require a persistent volume.

Forgejo CI in the sister `ha-tablet` repository builds every push to `main`,
publishes the image, then commits its exact commit tag and digest to
`ha-tablet/Dockerfile` here. A repository-scoped GitHub deployment key is stored
in Forgejo's `HOMELAB_NIX_DEPLOY_KEY` secret. Superseded builds are skipped and
concurrent Git updates are retried. GitOps applies the new pin automatically;
Dependabot ignores this image. To roll back, restore a previous `FROM` line.

The NAS Caddy forwards this hostname to the new Caddy. The old container and
runtime configuration remain available for rollback.

```sh
systemctl status podman-ha-tablet.service
journalctl -u podman-ha-tablet.service -n 30 --no-pager
```

## Authelia

`authelia/config.nix` is the source of truth for settings, access rules and OIDC
clients. Edit it, commit and push to `main`; GitOps renders the configuration
and recreates Authelia. The runtime configuration is read-only. Credentials,
signing/encryption keys and the user database are in `authelia/secrets.yaml`.
Edit them with SOPS; keys ending in `_json` contain a JSON-encoded value
(including string quotes), preserving multiline keys and special characters.
The user database is ordinary YAML stored as one encrypted string.

The image is pinned to the migrated `4.39.16` digest. `/srv/authelia/data`
preserves the complete SQLite identity store, MFA registrations, OIDC grants,
consents and notifier files. Startup requires `/srv/authelia/.migration-complete`;
restore that marker only with verified data. Backups and verification evidence
are retained under `/srv/authelia/migration-20261031` with restricted permissions.
The original NAS container and data remain available for rollback.

Caddy serves `https://login.lesicnik.eu` through `authelia:9091` on `proxy`.
The NAS Caddy forwards the login portal and HA Phone's authorization requests
to the new host. Existing OIDC issuer, clients, keys and callbacks are preserved.
Sessions use the original in-memory provider, so migration or restart requires
signing in again. Password changes must be applied to the encrypted user
database through GitOps, matching the original read-only user file.

```sh
systemctl status podman-authelia.service
journalctl -u podman-authelia.service -n 30 --no-pager
```

## AdGuard Home

The image is pinned to `v0.107.79` in `adguard/Dockerfile`. This is a fresh
installation; no settings, users, certificates or query history are imported.
Volumes `adguard-work` and `adguard-conf` persist state on `/srv`.

The rootless container uses host networking to preserve DNS client IPs. The
unprivileged port threshold is 53; only TCP/UDP 53 is allowed on
the LAN interface. Admin TCP 3001 is not opened to the LAN; Caddy reaches it
locally. AdGuard does not join `proxy` or claim Caddy's ports 80/443.

Setup is complete and port 3000 is closed. For a fresh installation, temporarily
allow TCP 3000 on `ens18` and open `http://192.168.10.20:3000`.
Select **All interfaces,
port 3001 for the admin interface**, and **192.168.10.20, port 53 for DNS**;
port 80 is already occupied by Caddy. Create your account in the wizard.
Caddy serves `https://adguard.lesicnik.eu` through `host.containers.internal:3001`
after setup. Close setup port 3000 again when finished.
Configure upstream resolvers explicitly rather than using the
host resolver, which still points to the old DNS server.

The old DNS service, router/DHCP settings, host nameserver and
`dns.lesicnik.eu` DoH route remain unchanged. Verify DNS over TCP and UDP on
`.20` before switching clients. Encrypted DNS requires separate configuration;
no unused encrypted-DNS or DHCP ports are opened for this bare service.

```sh
systemctl status podman-adguardhome.service
journalctl -u podman-adguardhome.service -n 30 --no-pager
```

## DDNS Updater

Edit records in `ddns-updater/config.nix`, then commit and push to `main`.
GitOps generates fresh configuration and recreates `ddns-updater` whenever an
entry is added, removed, or changed. Credential changes also restart it.

The Cloudflare token is encrypted in `ddns-updater/secrets.yaml`. Configuration
is passed through a SOPS-rendered `CONFIG` environment variable; the persistent
`ddns-updater-data` volume holds update history, not the managed configuration.
The existing Caddy route serves `https://ddns.lesicnik.eu` over `proxy`.
Timezone `Europe/Ljubljana` and upstream DNS `8.8.8.8` match the Compose stack.
The image is pinned to `2.10.0`; change its version in `ddns-updater/Dockerfile`
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

The hub image is pinned to `0.21.1` in `beszel/Dockerfile`. Volume `beszel-data`
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

Litara uses image tag `1.41.1`; PostgreSQL uses `16.15-alpine`.
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

The image uses tag `5.1.3-ls278`. The complete
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

## Prowlarr

The image uses tag `release-2.6.5.5623`. The complete
configuration is at `/srv/prowlarr/config`, including the database, indexers,
application connections, credentials, history, logs and backups. The existing
Sonarr and Radarr application URLs remain unchanged.

Caddy serves `https://prowlarr.lesicnik.eu` through `prowlarr:9696` on `proxy`.
Startup requires `/srv/prowlarr/.migration-complete`, created after file and
database verification. Preserve that marker with a verified restore. The full
configuration archive, checksum manifests and database checks are retained in
`/srv/prowlarr/migration-20261030` with restricted permissions. The stopped NAS
container and its original volume remain available for rollback.

```sh
systemctl status podman-prowlarr.service
journalctl -u podman-prowlarr.service -n 30 --no-pager
```

## Sonarr and Radarr

The image tags are `release-4.0.20.3014` for Sonarr and
`release-6.4.4.10685` for Radarr. Complete configurations, databases, artwork, credentials,
profiles, history and backups live in `/srv/sonarr/config` and
`/srv/radarr/config`. Download clients, indexers and remote path mappings retain
their existing settings and public URLs.

The NAS media stays on NFS with the original container paths:

| Container | `/data` | `/downloads` |
| --- | --- | --- |
| Sonarr | `/mnt/media/tv` | `/mnt/media/download/tv` |
| Radarr | `/mnt/media/movies` | `/mnt/media/download` |

UID/GID `1000` maps to the NAS identity through Podman's `keep-id` mode. Both
services require the NFS mount and their own `/srv/<name>/.migration-complete`
marker. Preserve the marker with a verified restore. Full configuration
archives, file checksums and database checks are retained in each service's
`/srv/<name>/migration-20261030` directory with restricted permissions. The old
NAS containers are stopped, with their original volumes retained for rollback.

Caddy serves `https://sonarr.lesicnik.eu` and `https://radarr.lesicnik.eu`
through `sonarr:8989` and `radarr:7878` on `proxy`.

```sh
systemctl status podman-sonarr.service podman-radarr.service
journalctl -u podman-sonarr.service -u podman-radarr.service -n 30 --no-pager
```

## qBittorrent

The image in `qbittorrent/Dockerfile` is pinned to the migrated `5.1.4` image
digest. `/srv/qbittorrent/config` preserves settings, torrents and resume state;
payload files remain on the NAS, with `/mnt/media` mounted at the original
`/media` path. Rootless UID/GID mapping matches the NAS identity, and startup
requires the real NFS mount and `/srv/qbittorrent/.migration-complete` marker.

The peer port is TCP/UDP `30054`. The WebUI stays internal on `1234`, served by
Caddy at `https://torrent.lesicnik.eu`. Keep any router forwarding pointed at
`192.168.10.20:30054`. Radarr/Sonarr retain the same HTTPS hostname, categories
and remote path mappings. The copied authentication whitelist additionally
trusts the new Podman proxy subnet, matching the old proxy's existing access.
Migration backup and inventory are retained in `/srv/qbittorrent/migration-20261030`.
