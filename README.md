# homelab-nix

NixOS homelab configs. GitOps checks `main` every minute and applies new commits.

[Container stacks](stacks/README.md) · [Encrypted secrets](secrets.md)

## Host: `docker`

Proxmox, x86-64, SeaBIOS.

| Setting | Value |
| --- | --- |
| SSH | `root@192.168.10.20` or `containers@192.168.10.20` |
| Network | `ens18`, `192.168.10.20/24` |
| Gateway / DNS | `192.168.10.1` / `192.168.10.9` |
| OS disk | `scsi0`, 32 GiB |
| Container disk | `scsi1`, 200 GiB, ext4 at `/srv` |
| Container user | UID/GID `1000`, home `/srv/podman` |
| Podman socket | `/run/user/1000/podman/podman.sock` |

Reserve `.20` outside DHCP. Run Podman as `containers`; Docker and the rootful
API are disabled. Container services require `/srv`. Back up important volumes.

## Install

Boot the NixOS ISO with networking. Check the SSH key in
`hosts/docker/default.nix` and push changes before installing.

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
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- --mode format,mount --flake "path:$PWD#docker"
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
sudo nixos-install --flake /mnt/etc/nixos#docker
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
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- --mode mount --flake "path:$PWD#docker"
```

Continue at install step 4. For an empty replacement OS disk, start at step 2,
skip step 3, then continue at step 4.

## Updates

Commit and push to `main`. To check immediately, run as root:

```sh
systemctl start nixos-upgrade.service
journalctl -u nixos-upgrade.service -n 30 --no-pager
```

Pause with `systemctl stop nixos-upgrade.timer`. Reboots are manual.
Update dependencies with `nix flake update`; keep `system.stateVersion` and
container UID/GID mappings unchanged. GitOps uses the remote branch, not `/etc/nixos`.
