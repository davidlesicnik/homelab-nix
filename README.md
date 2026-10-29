# homelab-nix

NixOS homelab configs. Hosts check `main` every minute and apply new commits.

## Rootless Podman host

Proxmox, x86-64, SeaBIOS. SSH as `containers@192.168.10.20` to run containers,
or `root@192.168.10.20` for host administration, using your key.
The hostname and flake target remain `docker` so existing GitOps keeps working.

| Setting | Value |
| --- | --- |
| Network | `ens18`, `192.168.10.20/24` |
| Gateway / DNS | `192.168.10.1` / `192.168.10.9` |
| OS disk | `scsi0`, 32 GiB |
| Container disk | `scsi1`, 200 GiB, ext4 at `/srv` |
| Container user | `containers`, UID/GID `1000`, home `/srv/podman` |
| Rootless storage | `/srv/podman/.local/share/containers/storage` |
| Rootless API socket | `/run/user/1000/podman/podman.sock` |

Reserve `.20` or exclude it from the router's DHCP pool.
Container storage is excluded from Disko, automatic formatting and pruning are
off, and the container user's services require the data mount. Keep separate
backups of important volumes. The user has subordinate UID/GID range
`100000–165535`, no administrative groups, and lingering enabled so user services
start at boot and continue after logout. Docker and the rootful Podman API are
disabled.

## Fresh installation

Boot the NixOS ISO with networking. Verify your public key in
`hosts/docker/default.nix` and push changes to `main` before installing.
**This procedure assumes empty disks. For existing data, see Reinstall below.**

### 1. SSH into the live ISO (optional)

In the Proxmox console:

```sh
sudo passwd nixos
sudo systemctl start sshd
ip -4 -br addr
```

On your workstation, replace `VM_IP` with the ISO's address:

```sh
ssh nixos@VM_IP
```

### 2. Clone and check

Run on the live ISO as `nixos`; stay in the repository for the remaining steps:

```sh
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git --command git clone https://github.com/davidlesicnik/homelab-nix.git
cd homelab-nix
ls -l /dev/disk/by-id/
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
nix --extra-experimental-features 'nix-command flakes' flake check --no-build --all-systems path:.
```

Confirm `drive-scsi0` is the 32 GiB OS disk and `drive-scsi1` is the 200 GiB data
disk. Stop if the IDs or layout differ. No hardware-config generation is needed.

### 3. Prepare the OS disk only

Keep both `sudo` and the standalone `--` after `path:.#disko`:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- --mode format,mount --flake "path:$PWD#docker"
findmnt --mountpoint /mnt
```

### 4. Initialize container storage — ONCE

**Skip this step if the data filesystem already exists, including on reinstalls
and when switching from Docker.**

```sh
sudo bash scripts/initialize-container-disk.sh
```

Check the disk identity and type the exact confirmation printed by the script.
It refuses existing storage; do not bypass its checks.

### 5. Mount container storage

```sh
sudo udevadm settle
sudo mkdir -p /mnt/srv
sudo mount /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 /mnt/srv
findmnt --mountpoint /mnt/srv
```

Confirm a separate ext4 mount from `scsi1`. A mount failure is not a reason to format.

### 6. Install

```sh
sudo mkdir -p /mnt/etc/nixos
sudo cp -a . /mnt/etc/nixos/
sudo chown -R root:root /mnt/etc/nixos
sudo nixos-install --flake /mnt/etc/nixos#docker
```

Set the root console password. After installation succeeds:

```sh
sudo poweroff
```

Eject the ISO in Proxmox, boot from `scsi0`, and keep `scsi1` attached.

### 7. Connect and verify

On your workstation:

```sh
ssh -i ~/.ssh/id_ed25519 containers@192.168.10.20
```

On the installed host:

```sh
findmnt --mountpoint /srv
id
podman info --format '{{.Host.Security.Rootless}} {{.Store.GraphRoot}} {{.Store.GraphDriverName}}'
systemctl --user is-active podman.socket
podman compose version
podman run --rm docker.io/library/alpine:latest id
```

Expect UID/GID `1000`,
`true /srv/podman/.local/share/containers/storage overlay`, and an `active`
user socket. The Alpine command should succeed; `uid=0` inside the container maps
to the unprivileged `containers` user on the host.

Run `podman` and `podman compose` as `containers`. Running them as root uses a
different, rootful store. Docker API clients can use
`DOCKER_HOST=unix:///run/user/1000/podman/podman.sock` from this user's session.

The user `podman-restart.service` restores containers with `--restart=always`
or `--restart=unless-stopped` at boot. Compose files and deployment automation
remain in their separate repository. For explicit user services, place Quadlets
under `~/.config/containers/systemd/` with `[Install] WantedBy=default.target`.

Rootless published ports must be `1024` or higher by default (for example,
`8080:80`). Open any required host firewall ports explicitly in the host config.
See the [Podman rootless guide](https://github.com/containers/podman/blob/v5.8.9/docs/tutorials/rootless_tutorial.md)
and [Quadlet documentation](https://docs.podman.io/en/stable/markdown/podman-systemd.unit.5.html).

## Reinstall without losing container data

**Never rerun container disk initialization.** To reuse the OS filesystem, clone the repo
in the live ISO and mount it without formatting:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- --mode mount --flake "path:$PWD#docker"
```

Continue from **step 5**. For an empty replacement OS disk, use step 3 instead,
then step 5. Preserve `scsi1` and its backing storage throughout.

## Updates

Edit, commit and push from your workstation. The host checks Git every minute,
rebuilding only for a new commit. Runs do not overlap; reboots remain manual.
To check immediately or inspect logs, run on the host as root:

```sh
systemctl start nixos-upgrade.service
journalctl -u nixos-upgrade.service -n 30 --no-pager
```

Pause automatic updates with `systemctl stop nixos-upgrade.timer`.

Update `flake.lock` intentionally with `nix flake update`; keep `system.stateVersion`
unchanged. Keep the container user's UID/GID and subordinate ranges unchanged on
reinstalls so existing ownership remains valid. Rebuilds do not format disks.
Rootless images and named volumes use the container disk; bind
mounts use the host path you choose.

Hosts live in `hosts/<name>/`, shared modules in `modules/nixos/`, and host
registrations in `flake.nix`. GitOps reads the remote branch directly; `/etc/nixos`
is the installation checkout and is not automatically pulled.
