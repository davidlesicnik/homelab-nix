# homelab-nix

Minimal NixOS homelab configurations. The first host is an existing x86-64
QEMU/Proxmox VM named `docker`, booting with legacy BIOS / SeaBIOS.

Start with [Fresh installation](#fresh-installation-of-the-docker-host).
For existing volumes, use [OS reinstallation](#reinstalling-the-os-while-keeping-docker-data).
After installation, follow [Manual updates](#manual-updates).

| Disk | Layout | Purpose |
| --- | --- | --- |
| Proxmox `scsi0` (32 GiB) | GPT, 1 MiB BIOS boot partition, ext4 `/` | NixOS and bootloader |
| Proxmox `scsi1` (200 GiB) | ext4 on the whole disk, mounted at `/var/lib/docker` | Docker named volumes, images, container data and logs |

The OS device is `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0`.
The Docker device is `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`.
These fixed IDs avoid dependence on `/dev/sda` and `/dev/sdb` ordering. The
OS root mount uses its partition label. No swap is configured.
The installed host uses static IPv4 networking on `ens18`:

| Setting | Value |
| --- | --- |
| Address | `192.168.10.20/24` |
| Gateway | `192.168.10.1` |
| DNS server | `192.168.10.9` |

These settings belong to `hosts/docker/default.nix`; shared server defaults
still use DHCP for future hosts. The live installer uses its own DHCP address.
Keep `192.168.10.20` outside the router's DHCP pool or reserve it for this VM
to prevent another device receiving the same address.
SSH allows keys only; the NixOS firewall opens port 22.
Docker and its Compose plugin are included. Docker uses `overlay2` and rotating
`local` logs, and requires the data mount before starting. The containerd image
store is explicitly disabled to keep image storage with the rest of Docker data.
Automatic Docker pruning is disabled. Old Nix generations are collected weekly
after 14 days.

Git is the source of truth. The Docker host is currently updated manually;
automatic Git pulls are disabled while the deployment workflow is being built.
The optional GitOps module remains available for later. Updates use the committed
`flake.lock`, and reboots remain manual. The repository is currently public,
so pulling over HTTPS needs no credentials.

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
modules/nixos/gitops.nix          # Optional pull workflow; not imported by Docker yet
scripts/initialize-docker-disk.sh # Explicit, guarded initialization of EMPTY scsi1
tests/initialize-docker-disk.sh   # Safety checks with mocked disk tools
```

Add future machines under `hosts/<name>/` and expose them as another entry in
`nixosConfigurations`. Import the shared modules each machine needs; hardware,
disks and `system.stateVersion` remain specific to each host. If you later enable
the GitOps module, it selects a configuration using `networking.hostName`, so keep
that name aligned with its entry in `nixosConfigurations`.

## Fresh installation of the Docker host

This guide installs the existing Proxmox VM. It assumes an x86-64 NixOS installer
ISO, **SeaBIOS / legacy BIOS**, a 32 GiB OS disk on `scsi0`, a 200 GiB Docker disk
on `scsi1`, and a network connection with DHCP and internet access. Keep both
disks attached. Enable the QEMU guest agent in Proxmox if you want guest status
and shutdown integration.

For a first installation, both disks must be empty. If Docker data already
exists, use [Reinstalling the OS while keeping Docker data](#reinstalling-the-os-while-keeping-docker-data).

### Before booting: workstation

Check that `users.users.root.openssh.authorizedKeys.keys` in
`hosts/docker/default.nix` contains your **complete public key line**. The current
configuration already includes David's key. Keep the matching private key on your
workstation. Commit and push any configuration changes, including `flake.lock`,
to `main` before installing. The current host applies updates only when you
explicitly rebuild it.

### 1. Boot the ISO and optionally connect over SSH

Open the VM's Proxmox console. The installer logs in as `nixos`. Check its IP:

```sh
ip -4 -br addr
```

If no LAN address is shown, configure networking with `nmtui` before continuing.
To work over SSH, run these commands **in the VM console**:

```sh
sudo passwd nixos
sudo systemctl start sshd
```

Set a temporary installer password. Then, **on your workstation**, replace
`VM_IP` with the VM's actual LAN address and connect:

```sh
ssh nixos@VM_IP
```

Use the password you just set. This login is for the live ISO; the repository's
SSH key and installed root account take effect after installation.
See the [NixOS installation manual](https://nixos.org/manual/nixos/stable/#sec-installation)
for the installer's SSH behavior.

### 2. Clone the repository: live ISO

Continue in the VM console or SSH session as `nixos`. All installer commands
below run on the VM. Commands needing root include `sudo`; keep using the
`nixos` shell and run the steps in order. Stop if a command fails.

```sh
cd ~
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git --command git clone --branch main https://github.com/davidlesicnik/homelab-nix.git
cd homelab-nix
```

If you already cloned it, use the existing directory and fetch the latest
committed instructions instead of cloning again:

```sh
cd ~/homelab-nix
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git --command git pull --ff-only
```

Stay in this directory through the installation. The commands include the Nix
feature flags explicitly, so no Nix settings need to be changed on the ISO.

### 3. Verify disks and configuration: live ISO

```sh
ls -l /dev/disk/by-id/
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
nix --extra-experimental-features 'nix-command flakes' flake check --no-build --all-systems path:.
```

Confirm the fixed IDs match this table. Ignore the ISO and its loop device.

| ID suffix | Size | Purpose |
| --- | --- | --- |
| `drive-scsi0` | 32 GiB | OS disk; Disko may create its partitions |
| `drive-scsi1` | 200 GiB | Docker data; separate one-time initialization only |

For a fresh installation, neither target disk should have partitions,
filesystems or mountpoints. If the device IDs or sizes differ, update the
host configuration and initializer in Git before proceeding. This repository
already provides the QEMU hardware configuration and filesystem declarations;
you do not need to run `nixos-generate-config`.

### 4. Prepare the empty OS disk: live ISO

This creates the OS partitions and ext4 filesystem on **`scsi0` only**, then
mounts the root filesystem at `/mnt`. It does not manage `scsi1`.

Copy this entire single-line command, including **`sudo`** and the standalone
**`--` immediately after `path:.#disko`**:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- --mode format,mount --flake "path:$PWD#docker"
```

`sudo` gives Disko permission to access the disk. The standalone `--` passes
`--mode` and the following arguments to Disko rather than to Nix.
Verify that the OS filesystem is mounted before continuing:

```sh
findmnt --mountpoint /mnt
```

It must show the ext4 root partition on the 32 GiB OS disk. To reuse an existing
OS filesystem, use the mount-only command in the reinstall section instead.

### 5. Initialize the EMPTY Docker disk once: live ISO

**Run this only for the first installation on an empty `scsi1` disk.** If the
filesystem was already created during an earlier attempt, skip to step 6.
Never run initialization as part of an OS reinstall or routine update.

```sh
sudo bash scripts/initialize-docker-disk.sh
```

Check the displayed disk identity and type the following only if it is the
intended empty 200 GiB disk:

```text
INITIALIZE /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
```

The script creates ext4 directly on the whole disk, with label `docker-data`.
It refuses existing storage. If it refuses, inspect the disk; do not remove
signatures, add force flags or substitute a raw formatting command.

### 6. Mount Docker storage: live ISO

Use this step for both a newly initialized disk and an existing Docker data disk:

```sh
sudo udevadm settle
sudo mkdir -p /mnt/var/lib/docker
sudo mount /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 /mnt/var/lib/docker
findmnt --mountpoint /mnt/var/lib/docker
```

The last command must show a separate ext4 mount from `scsi1` at exactly
`/mnt/var/lib/docker`. If mounting fails, stop and inspect the disk. A mount
failure is not a reason to initialize it again.

### 7. Install NixOS: live ISO

From `~/homelab-nix`, copy the committed configuration onto the mounted OS disk
and make its bootstrap Git checkout owned by root:

```sh
sudo mkdir -p /mnt/etc/nixos
sudo cp -a . /mnt/etc/nixos/
sudo chown -R root:root /mnt/etc/nixos
sudo nixos-install --flake /mnt/etc/nixos#docker
```

Set the root console password when prompted. This is the installed system's
password, separate from the temporary `nixos` password on the ISO. Installed SSH
access uses the public key in Git; root password login over SSH is disabled.
The installer builds and installs this flake's `docker` configuration.

Wait for `nixos-install` to finish successfully, then power off:

```sh
sudo poweroff
```

### 8. Boot the installed system and reconnect

In Proxmox, eject the installer ISO, put `scsi0` first in the boot order, keep
`scsi1` attached, and start the VM. In its console, log in as `root` with the
password set during installation and check its IP:

```sh
ip -4 -br addr
```

The installed host uses `192.168.10.20`, which can differ from the ISO's DHCP
address. On your workstation, connect using your SSH key:

```sh
ssh root@192.168.10.20
```

The installed configuration does not create a `nixos` user. If SSH reports a
changed host key, see the troubleshooting section before replacing the saved
ISO key.

### 9. Verify the installed host

Run on the installed host as root:

```sh
findmnt --mountpoint /var/lib/docker
systemctl is-active docker
docker info --format '{{.DockerRootDir}} {{.Driver}} {{.LoggingDriver}}'
docker compose version
docker run --rm hello-world
docker volume ls
nixos-version --configuration-revision
```

Expected results:

- `/var/lib/docker` is a separate ext4 mount from `scsi1`.
- Docker is `active` and reports `/var/lib/docker overlay2 local`.
- Compose reports its version, and the disposable `hello-world` container succeeds.
- The configuration revision identifies the Git commit used for installation.

Named volumes live under `/var/lib/docker/volumes` on the data disk. Bind mounts
use the host path you specify; paths under `/home` or `/opt` still use the OS disk.

## Installation troubleshooting

| Symptom | Action |
| --- | --- |
| Disko reports error 13 or says to run as root | Use the exact step 4 command, including `sudo`. |
| Nix reports `unrecognised flag '--mode'` | Include the standalone `--` between `path:.#disko` and `--mode`. |
| Nix says `nix-command` or `flakes` is disabled | Use the explicit `--extra-experimental-features 'nix-command flakes'` flags shown above. |
| The initializer refuses an existing filesystem or disk signature | Skip initialization if the expected Docker filesystem already exists; inspect it before mounting. Do not force a format. |
| A mount is already mounted after retrying a step | Check it with the corresponding `findmnt --mountpoint` command and continue only if the source and target are correct. |
| SSH as `nixos` fails after installation | Connect as `root` using the private key matching the public key in the repository. |

The installed system generates different SSH host keys from the live ISO.
If the workstation reports a changed key, confirm the VM's address and inspect
the new fingerprint **from the installed VM's Proxmox console**:

```sh
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Only after confirming that this is the VM you installed, remove its saved ISO
key **on your workstation**, reconnect, and compare the presented fingerprint:

```sh
ssh-keygen -R 192.168.10.20
ssh root@192.168.10.20
```

## Reinstalling the OS while keeping Docker data

Keep `scsi1` and its backing storage intact. As an extra boundary when replacing
or repartitioning the OS disk, temporarily detach `scsi1` in the VM settings
without deleting its storage. Disko targets only the fixed `scsi0` ID.
Boot the ISO and clone/validate the committed configuration as described above.
For a new, empty replacement OS disk, use fresh-install step 4. To reuse an
already prepared OS filesystem, run this **mount-only** command from the repository:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#disko -- --mode mount --flake "path:$PWD#docker"
```

Reconnect `scsi1` when OS preparation is complete. If reconnecting it requires
rebooting the ISO, run the mount-only command again afterward to restore `/mnt`.
Then continue from fresh-install **step 6** to mount its existing filesystem,
install NixOS and boot the host. **Skip step 5 entirely**: never run the Docker
initializer for a reinstall. Docker reuses the volumes and other data on `scsi1`.
This configuration expects ext4 on the whole data disk; an existing disk with a
different layout needs a matching mount declaration in Git, not reformatting.

## Manual updates

Make changes in your workstation checkout, validate them and commit/push to
`main`. Then explicitly pull and rebuild on the installed host. Updating
`flake.lock` is a repository change too:

```sh
nix flake update
nix flake check --no-build --all-systems path:.
git add flake.nix flake.lock hosts modules scripts tests README.md
git commit -m "Update homelab configuration"
git push origin main
```

Omit `nix flake update` when only changing host configuration. On the installed
host, run as root:

```sh
cd /etc/nixos
git pull --ff-only
nixos-rebuild switch --flake /etc/nixos#docker
nixos-version --configuration-revision
```

The deployed Git revision is recorded in the system generation. Keep `/etc/nixos`
as the host's checkout and make persistent edits on your workstation. Direct
manual rebuilds can also read the committed configuration from Git:

```sh
sudo nixos-rebuild switch --refresh --no-update-lock-file \
  --flake 'git+https://github.com/davidlesicnik/homelab-nix.git?ref=main#docker'
```

Rebuilds apply configuration and mount existing filesystems. Neither Disko nor
the Docker disk initializer is part of an update.
Keep `system.stateVersion` at the initial installation version when updating inputs.

To undo a bad deployment, revert its commit on `main`, then pull and rebuild.
For immediate recovery, switch to the previous generation from the VM console:

```sh
sudo nixos-rebuild switch --rollback
```

An older generation can have a different IP address and may enable the earlier
GitOps timer; stop that timer if rolling back to it. After the fix is committed
and pushed, pull and rebuild manually. A failed evaluation or build leaves the
running generation unchanged. Kernel changes take effect on the next manual
reboot. If the repository becomes private, provision
read-only Git credentials on each host before changing the pull URL; keep those
credentials out of Nix files.

## Optional GitOps workflow

`modules/nixos/gitops.nix` is prepared but not currently imported by the Docker
host. When the deployment workflow is ready, enable its import in
`hosts/docker/default.nix` and apply that configuration manually. It will then
pull `main` every 15 minutes, with up to 60 seconds of jitter, select the host's
configuration by hostname, honor `flake.lock`, and leave reboots manual.

Run the initializer's safety tests on a workstation with Bash:

```sh
bash tests/initialize-docker-disk.sh
```

The tests replace disk inspection and formatting tools with mocks; no disk is opened.

NixOS [Docker module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/virtualisation/docker.nix),
NixOS [automatic upgrade module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/tasks/auto-upgrade.nix),
Disko [installation documentation](https://github.com/nix-community/disko/blob/master/docs/quickstart.md),
Docker [storage documentation](https://docs.docker.com/engine/storage/containerd/).
