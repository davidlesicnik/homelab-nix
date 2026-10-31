# Secrets

SOPS + age. Encrypted credentials live in `stacks/<name>/secrets.yaml` or
`hosts/<host>/secrets.yaml`;
public recipients live in `.sops.yaml`.

## Edit

```sh
nix develop --command sops stacks/caddy/secrets.yaml
```

Commit and push. NixOS decrypts into `/run/secrets` and restarts affected services.
For another stack, use the same command with its path and follow Caddy's
`sops.secrets` / `sops.templates` declarations.

## Keys

- Host: `/var/lib/sops-nix/key.txt`, `root:root`, mode `0600`.
- Workstation: `~/Library/Application Support/sops/age/keys.txt`.
- Linux: `~/.config/sops/age/keys.txt`.
- Override: `SOPS_AGE_KEY_FILE`.

Both NixOS hosts have separate age identities. The Plex host's identity is also
backed up on this Mac at `~/.config/homelab-nix/plex-sops/keys.txt`; preserve it
when reinstalling or moving administration to another machine. New Plex LXCs
need their own provisioned identity before enabling encrypted host secrets.

Back up private keys outside Git. Restore the host key when reinstalling;
see [installation](README.md#install). The workstation key can recover credentials
if a host key is lost.

## New or replacement host

Generate its age key outside the repo, install it at the host path above,
and add its public recipient to `.sops.yaml`. Re-encrypt existing files:

```sh
nix develop --command sops updatekeys stacks/caddy/secrets.yaml
```

Commit the recipient and ciphertext changes before enabling the stack.
