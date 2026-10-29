# homelab-nix

Minimal NixOS homelab configurations. The first host is an existing x86-64
QEMU/Proxmox VM named `docker`, booting with legacy BIOS / SeaBIOS.

| Disk | Layout | Purpose |
| --- | --- | --- |
| Proxmox `scsi0` (32 GiB) | GPT, 1 MiB BIOS boot partition, ext4 `/` | NixOS and bootloader |
| Proxmox `scsi1` (200 GiB) | ext4 on the whole disk, mounted at `/var/lib/docker` | Docker named volumes, images, container data and logs |

The OS device is `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0`.
The Docker device is `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`.
These fixed IDs avoid dependence on `/dev/sda` and `/dev/sdb` ordering. The
OS root mount uses its partition label. No swap is configured.
Networking uses DHCP. SSH allows keys only; the NixOS firewall opens port 22.
Docker and its Compose plugin are included. Docker uses `overlay2` and rotating
`local` logs, and requires the data mount before starting. The containerd image
store is explicitly disabled to keep image storage with the rest of Docker data.
Automatic Docker pruning is disabled. Old Nix generations are collected weekly
after 14 days.

Git is the source of truth. Once installed, the host pulls `main` from this
repository every 15 minutes (plus up to 60 seconds of jitter) and applies
`nixosConfigurations.docker`. Updates use the committed `flake.lock` without
updating inputs on the host. Reboots remain manual. The repository is currently
public, so pulling over HTTPS needs no credentials.

## Docker data protection

The Docker disk is **not managed by Disko**. Its NixOS configuration only mounts
the existing ext4 filesystem, with `autoFormat = false`. Disko only knows about
the OS disk, and destructive disk wiping is disabled there too (`destroy = false`).
Configuration assertions reject adding another Disko disk, enabling automatic
formatting of Docker storage, or using the Docker device as the OS disk.
GitOps updates and routine rebuilds never call a formatter. If the Docker disk
is missing or cannot mount, Docker cannot start; it does not fall back to writing
into the OS disk's mount directory. Automatic Docker pruning is disabled.

The separate initializer in `scripts/initialize-docker-disk.sh` is for the first
installation on the confirmed empty `scsi1` disk. It is never called by NixOS or
the update timer. It only targets the fixed `scsi1` ID, rejects arbitrary device
arguments, refuses partitions, mounts, swap and existing disk signatures, and
requires typing the full device ID before creating a filesystem. There is no
force or reformat option. Once data exists, mount it and skip initialization.

These guards protect the repository's provisioning and update paths. Back up
important volumes separately: manual root commands, VM disk deletion and storage
failure can still destroy data. NixOS rollback does not restore volume contents.

## Repository layout

```text
flake.nix                         # Pinned inputs and explicit host definitions
hosts/docker/default.nix          # Host identity and SSH keys
hosts/docker/hardware-configuration.nix
hosts/docker/disk-config.nix      # OS layout and mount-only Docker filesystem
modules/nixos/common.nix          # Shared minimal server settings
modules/nixos/docker.nix          # Docker service and data-mount dependency
modules/nixos/gitops.nix          # Pull and apply this host's configuration from Git
scripts/initialize-docker-disk.sh # Explicit, guarded initialization of EMPTY scsi1
tests/initialize-docker-disk.sh   # Safety checks with mocked disk tools
```

Add future machines under `hosts/<name>/` and expose them as another entry in
`nixosConfigurations`. Import the shared modules each machine needs; hardware,
disks and `system.stateVersion` remain specific to each host. The GitOps module
selects a configuration using `networking.hostName`, so keep that name aligned
with its entry in `nixosConfigurations`.

## Initial installation on the existing VM

Run these commands **inside the VM's NixOS live installer**. There is no VM
creation step. This procedure is for the confirmed empty disks only.

Before using the installer, add your public SSH key to
`users.users.root.openssh.authorizedKeys.keys` in `hosts/docker/default.nix`
on your workstation. Commit and push all configuration changes, including
`flake.lock`, to `main`. Without an SSH key, the installed system remains
accessible through the VM console using the root password set during installation.

1. In the installer, clone the committed configuration:

   ```sh
   nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git --command \
     git clone https://github.com/davidlesicnik/homelab-nix.git
   cd homelab-nix
   ```

2. Confirm the VM uses SeaBIOS and verify the disks:

   ```sh
   lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS
   ```

   Confirm that `drive-scsi0` is the 32 GiB OS disk and `drive-scsi1` is the
   200 GiB Docker disk. The configuration already uses those fixed IDs.

3. Validate the configuration before writing to the disks:

   ```sh
   nix --extra-experimental-features 'nix-command flakes' flake check --no-build path:.
   ```

4. Provision the **empty OS disk only** and mount it below `/mnt`.
   The Docker disk is outside this Disko configuration:

   ```sh
   sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- \
     --mode format,mount --flake "path:$PWD#docker"
   ```

   To reuse an existing OS filesystem, use `--mode mount` instead.

5. **Only for the very first installation on empty `scsi1`**, initialize its
   filesystem explicitly. Skip this command if the Docker disk already has data:

   ```sh
   sudo bash scripts/initialize-docker-disk.sh
   ```

   This prints the disk identity and asks you to type
   `INITIALIZE /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`.
   If it refuses, investigate the existing storage; do not wipe signatures or
   force a format. For both new and existing Docker filesystems, mount the data disk:

   ```sh
   sudo udevadm settle
   sudo mkdir -p /mnt/var/lib/docker
   sudo mount /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 /mnt/var/lib/docker
   findmnt /mnt/var/lib/docker
   ```

6. Keep a copy of the configuration on the installed system and install NixOS:

   ```sh
   sudo mkdir -p /mnt/etc/nixos
   sudo cp -a . /mnt/etc/nixos/
   sudo nixos-install --flake /mnt/etc/nixos#docker
   ```

   Set the root console password when prompted. Detach the installer ISO and
   reboot, with the 32 GiB disk first in the VM's boot order.

7. Check the installed host from its console, or over SSH if a key was added:

   ```sh
   findmnt /var/lib/docker
   systemctl is-active docker
   docker info --format '{{.DockerRootDir}} {{.Driver}} {{.LoggingDriver}}'
   docker compose version
   docker run --rm hello-world
   docker volume ls
   ```

   The mount must be the data disk, the Docker root must be `/var/lib/docker`,
   and named volumes will be below `/var/lib/docker/volumes`.
   Bind mounts use whichever host
   path you specify, so a bind mount from `/home` or `/opt` still uses the OS disk.

## Reinstalling the OS while keeping Docker data

Keep `scsi1` and its backing storage intact. As an extra boundary when replacing
or repartitioning the OS disk, temporarily detach `scsi1` in the VM settings
without deleting its storage. Disko targets only the fixed `scsi0` ID.
Reconnect `scsi1` when OS preparation is complete, mount its existing filesystem
as shown above, and install NixOS. Never run the Docker initializer for a reinstall.
Docker reuses the volumes and other data already on `scsi1`.

## GitOps updates

Make changes in your workstation checkout, validate them and commit/push to
`main`. Each host fetches that branch and applies its own configuration on the
next timer run. Updating `flake.lock` is a repository change too:

```sh
nix flake update
nix flake check --no-build --all-systems path:.
git add flake.nix flake.lock hosts modules scripts tests README.md
git commit -m "Update homelab configuration"
git push origin main
```

Omit `nix flake update` when only changing host configuration. On the installed
host, apply the latest committed state immediately or inspect automatic updates:

```sh
sudo systemctl start nixos-upgrade.service
systemctl list-timers nixos-upgrade.timer
journalctl -u nixos-upgrade.service -n 50 --no-pager
nixos-version --configuration-revision
```

The deployed Git revision is recorded in the system generation. The copy under
`/etc/nixos` is a bootstrap checkout; the timer fetches the remote branch directly.
Edit the repository on your workstation for persistent changes. Direct rebuilds
can also pull from Git without updating a local checkout:

```sh
sudo nixos-rebuild switch --refresh --no-update-lock-file \
  --flake 'git+https://github.com/davidlesicnik/homelab-nix.git?ref=main#docker'
```

Rebuilds apply configuration and mount existing filesystems. Neither Disko nor
the Docker disk initializer is part of a GitOps update.
Keep `system.stateVersion` at the initial installation version when updating inputs.

To undo a bad deployment, revert its commit on `main` and let the host pull again.
For immediate recovery, stop the timer before switching to the previous generation;
the timer would otherwise reapply the bad commit:

```sh
sudo systemctl stop nixos-upgrade.timer nixos-upgrade.service
sudo nixos-rebuild switch --rollback
```

After the fix is committed and pushed, start `nixos-upgrade.service` and then
`nixos-upgrade.timer` again. A failed evaluation or build leaves the running
generation unchanged; inspect the journal for activation failures. Kernel changes
take effect on the next manual reboot. If the repository becomes private, provision
read-only Git credentials on each host before changing the pull URL; keep those
credentials out of Nix files.

Run the initializer's safety tests on a workstation with Bash:

```sh
bash tests/initialize-docker-disk.sh
```

The tests replace disk inspection and formatting tools with mocks; no disk is opened.

NixOS [Docker module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/virtualisation/docker.nix),
NixOS [automatic upgrade module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/tasks/auto-upgrade.nix),
Disko [installation documentation](https://github.com/nix-community/disko/blob/master/docs/quickstart.md),
Docker [storage documentation](https://docs.docker.com/engine/storage/containerd/).
