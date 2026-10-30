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

## DDNS Updater

Edit records in `ddns-updater/config.nix`, then commit and push to `main`.
GitOps generates fresh configuration and recreates `ddns-updater` whenever an
entry is added, removed, or changed. Credential changes also restart it.

The Cloudflare token is encrypted in `ddns-updater/secrets.yaml`. Configuration
is passed through a SOPS-rendered `CONFIG` environment variable; the persistent
`ddns-updater-data` volume holds update history, not the managed configuration.
The existing Caddy route serves `https://ddns.lesicnik.eu` over `proxy`.
Timezone `Europe/Ljubljana` and upstream DNS `8.8.8.8` match the Compose stack.

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
