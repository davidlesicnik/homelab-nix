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
