# homelab-nix

NixOS homelab configs. Hosts apply updates from `main` through GitOps.

[Container stacks](stacks/README.md) · [Encrypted secrets](secrets.md)

[Plex Proxmox LXC template](hosts/plex/README.md) — Intel transcoding, NAS media,
and migration notes for the existing Docker Plex server.

## Monitoring

Both hosts run a native `beszel-agent` service, connecting outward to
`https://beszel.lesicnik.eu` over HTTPS; no agent port is opened. The `podman`
agent runs as `containers` to monitor rootless Podman and includes `/srv` usage.
The `plex` agent monitors the LXC. Registration tokens are SOPS-encrypted in
`hosts/<host>/secrets.yaml`. The agent version and release checksum are pinned in
`modules/nixos/beszel-agent-package.nix`; update them alongside the Beszel hub.

Check with `systemctl status beszel-agent` and
`journalctl -u beszel-agent -n 30 --no-pager` on either host.

## Host: `podman`

Proxmox, x86-64, SeaBIOS.

| Setting | Value |
| --- | --- |
| SSH | `root@192.168.10.20` or `containers@192.168.10.20` |
| Network | `ens18`, `192.168.10.20/24` |
| Gateway / DNS | `192.168.10.1` / `192.168.10.20` |
| OS disk | `scsi0`, 32 GiB |
| Container disk | `scsi1`, 200 GiB, ext4 at `/srv` |
| Media mount | `192.168.10.9:/volume1/media` (NFS) at `/mnt/media`, mounted on access |
| Container user | UID/GID `1000`, home `/srv/podman` |
| Podman socket | `/run/user/1000/podman/podman.sock` |

Reserve `.20` outside DHCP. Run Podman as `containers`; Docker and the rootful
API are disabled. Container services require `/srv`. Back up important volumes.

The NFS server controls media permissions; allow the container user's UID/GID
`1000` as needed. After applying the configuration, run `ls /mnt/media` to
trigger the mount and `findmnt --mountpoint /mnt/media` to verify it.

## Install

Boot the NixOS ISO with networking. Check the SSH key in
`hosts/podman/default.nix` and push changes before installing.

### 1. Clone and verify disks

```sh
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git --command git clone https://github.com/davidlesicnik/homelab-nix.git
cd homelab-nix
ls -l /dev/disk/by-id/
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
nix --extra-experimental-features 'nix-command flakes' flake check --no-build --all-systems path:.
```

Confirm `drive-scsi0` is the OS disk and `drive-scsi1` is the data disk.

### 2. Format and mount the OS disk

**This erases the OS disk.** For an existing installation, see Reinstall below.

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- --mode format,mount --flake "path:$PWD#podman"
findmnt --mountpoint /mnt
```

### 3. Initialize an empty data disk only

**Skip if the data filesystem already exists. Never run this on reinstalls.**

```sh
sudo bash scripts/initialize-container-disk.sh
```

### 4. Mount data, restore the host's age key, install

```sh
sudo udevadm settle
sudo mkdir -p /mnt/srv
sudo mount /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 /mnt/srv
findmnt --mountpoint /mnt/srv
```

Confirm a separate ext4 mount before continuing. The age key must match the
host recipient in `.sops.yaml`.

```sh
sudo install -D -m 0600 /path/to/backed-up-host-key.txt /mnt/var/lib/sops-nix/key.txt
sudo mkdir -p /mnt/etc/nixos
sudo cp -a . /mnt/etc/nixos/
sudo chown -R root:root /mnt/etc/nixos
sudo nixos-install --flake /mnt/etc/nixos#podman
```

After installation succeeds, run `sudo poweroff`, eject the ISO, and boot from
`scsi0` with `scsi1` attached.

### 5. Verify

SSH as `containers@192.168.10.20`:

```sh
findmnt --mountpoint /srv
podman info --format '{{.Host.Security.Rootless}} {{.Store.GraphRoot}}'
systemctl --user is-active podman.socket
podman ps
```

Expect rootless `true`, storage under `/srv/podman`, and an active socket.

## Reinstall

Preserve `scsi1`; never initialize it again. To reuse the OS filesystem:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- --mode mount --flake "path:$PWD#podman"
```

Continue at install step 4. For an empty replacement OS disk, start at step 2,
skip step 3, then continue at step 4.

## Updates

Dependabot opens a weekly host-package PR for `nixpkgs`, `disko` and `sops-nix`
on Mondays at 08:30 Europe/Ljubljana. Nixpkgs tracks `nixos-26.05`; release upgrades
remain manual. Caddy uses its own `caddy-nixpkgs` pin and a separate weekly updater
that also refreshes its plugin and dependency hash. Host-only lock updates skip
Caddy builds. See [container updates](stacks/README.md#container-image-updates).

Open a PR and merge it into `main` after the required checks and owner review.
To check for a merged update immediately, run as root:

```sh
systemctl start nixos-upgrade.service
journalctl -u nixos-upgrade.service -n 30 --no-pager
```

Pause with `systemctl stop nixos-upgrade.timer`. Reboots are manual.
To refresh host dependencies manually, use `nix flake update nixpkgs disko sops-nix`.
Use `python3 scripts/update-caddy.py` on Linux for Caddy, so its hash is refreshed too.
Keep `system.stateVersion` and
container UID/GID mappings unchanged. GitOps uses the remote branch, not `/etc/nixos`.

## PR checks and ownership

`@davidlesicnik` owns every file through `.github/CODEOWNERS`, including the
ownership file and workflows. PRs run workflow and shell linting, Python tests,
mocked disk initialization guard tests, Nix evaluation for both hosts, and Caddy
and Plex builds when their inputs change. Caddy builds run for package, image,
or configuration changes and updates to its dedicated dependency pin. For
`flake.nix` edits, CI compares the Caddy image and configuration derivations
against the base revision; unrelated flake edits skip the build. Workflow,
updater, test, documentation, and host deployment edits alone do not trigger it.
Manual workflow dispatch still forces a build. GitHub Actions dependencies receive
weekly Dependabot updates; action references stay pinned to commit SHAs.

To enforce this policy, configure an active GitHub ruleset for `main` (repository
Settings → Rules → Rulesets):

- Require a pull request, one approval, and review from Code Owners.
- Dismiss stale approvals when new commits are pushed and require resolved conversations.
- Require status checks `build` (the Nix checks workflow) and `Plex PR checks`,
  with the branch up to date before merging. Select their GitHub Actions source.
- Block force pushes and branch deletion; keep the bypass list empty if admins
  should also follow these rules.

Land these files and let the checks run before selecting the required checks.
Do not require the conditional Plex `check` job: `Plex PR checks` reports success
when a build is unnecessary and fails if detection or a required build fails.
CODEOWNERS alone does not restrict writes or merges; the ruleset must be enabled
on GitHub. Other collaborators can still propose changes, but merging them requires
the owner's approval. GitHub does not allow authors to approve their own PRs, so
making the sole owner a required reviewer also blocks that owner's own PRs unless
another owner is added or an explicit bypass policy is configured.
