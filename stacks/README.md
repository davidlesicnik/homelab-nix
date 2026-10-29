# Container stacks

Each stack is a NixOS module in `stacks/<name>/default.nix`, with its container
definitions and related configuration kept together. A stack may contain one
container or several related containers, such as an app and its database.

Hosts import the stacks they need explicitly in `hosts/<host>/default.nix`.
The shared `modules/nixos/containers.nix` module provides rootless defaults,
data-mount dependencies, and the `proxy` network. Container definitions use
the native `virtualisation.oci-containers.containers` options.

For additional stacks:

1. Create `stacks/<name>/default.nix` and define its containers there. Prefix
   container names and named volumes with the stack name to avoid collisions.
2. Add `networks = [ "proxy" ];` to frontends Caddy needs to reach. Keep databases
   on a stack-specific private network when adding multi-container stacks.
3. Import the stack from the intended host. Open firewall ports only for services
   that need direct host access.
4. Keep encrypted credentials in `stacks/<name>/secrets.yaml` using SOPS.
   Declare `sops.secrets` and, when an environment file is needed, a
   `sops.templates` entry. Reference the template's runtime path through
   `environmentFiles`. Follow [the secrets workflow](../secrets.md).
5. Commit all new files and push to `main`. The host's existing GitOps service
   builds and switches to the new configuration.

Named volumes and images live in the container user's store on `/srv`.
Removing a stack stops its containers without deleting its named volumes.

## Caddy

`caddy/` preserves the routes from the sister Docker repository, the Cloudflare
DNS challenge plugin, and the shared `proxy` network. Docker-only upstream names
will become available as their stacks migrate to this host and join `proxy`.
No DNS or router changes are made by this configuration.

- Main configuration: `caddy/config/Caddyfile`.
- Additional sites: `caddy/config/sites/*.caddy`, imported automatically.
- Encrypted credential: `caddy/secrets.yaml`, editable with
  `nix develop --command sops stacks/caddy/secrets.yaml` from the repository root.
- Runtime environment: `/run/secrets/rendered/caddy.env`, decrypted by
  `sops-nix`, owned by `containers` with mode `0400`. A changed credential
  automatically restarts `podman-caddy.service`.
- Persistent volumes: `caddy-data` (certificates and access logs), `caddy-config`.
- HTTP: TCP 80. HTTPS: TCP/UDP 443. This stack lowers the host's unprivileged
  port threshold to 80 so rootless Podman can publish these ports.

Nix builds the Caddy image with the pinned Cloudflare plugin. It validates the
whole configuration before activation, using temporary storage and a dummy
token. All configuration files are mounted read-only from a content-addressed
store directory; changing the main file, adding a site, or removing a site
changes the service definition and restarts Caddy automatically. Certificates
and logs remain in persistent storage.

As root on the host, inspect the managed service with:

```sh
systemctl status podman-caddy.service
journalctl -u podman-caddy.service -n 50 --no-pager
```

As `containers`, use `podman ps` and `podman network inspect proxy` to inspect
containers and their shared network. These NixOS-managed containers are system
services running as `containers`; use the system service above for lifecycle
management.
