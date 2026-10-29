# Encrypted secrets

Stack credentials live in Git as SOPS-encrypted `stacks/<name>/secrets.yaml`
files. `.sops.yaml` contains public age recipients and creation rules; it has no
private keys. Each file is encrypted for both the administrator and the host.

NixOS decrypts secrets into `/run/secrets` at activation and boot. Environment
templates are rendered into `/run/secrets/rendered`, with access granted only
to the service user. Plaintext credentials and private identities never enter
the Nix store or container images. Services declare `restartUnits` on their
templates to pick up changed credentials automatically.

## Edit or add a credential

Run from the repository root:

```sh
nix develop --command sops stacks/caddy/secrets.yaml
```

SOPS uses your local age identity automatically. For this workstation, it is
`~/Library/Application Support/sops/age/keys.txt`; on Linux the default is
`~/.config/sops/age/keys.txt`. Use `SOPS_AGE_KEY_FILE` to select another identity.
Keep a secure backup of this identity so you can edit and recover secrets.

For another stack, create `stacks/<name>/secrets.yaml` with the same command.
The creation rule encrypts it for the configured recipients. Define the secret
and its environment template in the stack's `default.nix`, following Caddy's
example. Commit the encrypted file, declarations and any `.sops.yaml` changes,
then push to `main`. GitOps builds the configuration, decrypts on the host and
restarts affected services.

## The one bootstrap requirement

Each host needs its own private age identity at `/var/lib/sops-nix/key.txt`,
owned by `root:root` with mode `0600`. This is the only secret material that must
be provisioned outside Git. The configured path is the same on every host.
Do not place a private identity in the repository, even temporarily.

For a reinstall, restore the existing host identity before `nixos-install`:

```sh
sudo install -D -m 0600 /path/to/backed-up-host-key.txt /mnt/var/lib/sops-nix/key.txt
```

Keep this host identity in a secure backup. If it is lost, use the administrator
identity to re-encrypt the stack secrets for a replacement host identity.
Ciphertext and a public key alone cannot decrypt a secret.

## Add or replace a host

Generate its identity outside the repository, install it at the standard path,
and add only its public recipient to `.sops.yaml`. Include that recipient in
the creation rule for the stacks this host should run. Update existing files:

```sh
nix develop --command sops updatekeys stacks/caddy/secrets.yaml
```

Commit the changed recipients and ciphertext before enabling those stacks on
the new host. The host needs its own identity; the administrator's recovery
identity stays on the workstation or in its secure backup.
