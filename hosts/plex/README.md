# Plex LXC

Unprivileged x86-64 NixOS template for Proxmox, with Plex and Intel VA-API / Quick
Sync drivers. Proxmox controls networking, media mounts and GPU access. Plex data
is stored on the LXC root disk at `/var/lib/plex` (included in root-disk backups).
SSH uses the same public key as the `docker` host. GitHub Actions builds system
updates; the LXC checks for signed builds every two minutes and installs them
without building packages locally or rebooting automatically.

## Build

On an x86-64 Linux machine with Nix, from the repo root:

```sh
nix build path:.#plex-lxc
ls -lh result/tarball/nixos-plex-x86_64-linux.tar.xz
```

macOS cannot build this Linux image locally. After pushing these files, run
**Plex builds and updates** in GitHub Actions on `main` and download its artifact. Extract
the artifact ZIP to get the `.tar.xz` and `SHA256SUMS`; run `sha256sum -c SHA256SUMS`
on Linux to verify it. Download artifacts within one day. No claim token, Plex database or server identity is baked
into the image.

## Mount media on Proxmox

Use the same NAS export as the Docker VM, mounted **on the Proxmox node**.
If `/mnt/media` already contains another mount or files, use a dedicated path
instead and adjust the commands below. Add this line once to the node's
`/etc/fstab`:

```fstab
192.168.10.9:/volume1/media /mnt/media nfs ro,hard,_netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=0,x-systemd.mount-timeout=30s 0 0
```

This creates systemd's `mnt-media.automount` and `mnt-media.mount` units. The
automount mounts the share on access; `hard` keeps retrying NFS requests while
the NAS is unavailable, so reads resume after a normal NAS reboot. Playback may
pause during the outage. The 30-second timeout applies to establishing the mount,
not ongoing NFS recovery. Idle unmounting is disabled to keep the LXC bind mount
attached to the same filesystem; do not unmount/remount it during a NAS reboot.

```sh
mkdir -p /mnt/media
systemctl daemon-reload
systemctl start mnt-media.automount
systemctl is-active mnt-media.automount
ls /mnt/media
findmnt --mountpoint /mnt/media
```

Allow this Proxmox node to read the NAS export. Plex runs as UID/GID `1000:1000`
inside the LXC; with Proxmox's default unprivileged mapping that is
`101000:101000` on the node/NAS. NAS permissions must allow that identity to read
files and traverse directories, or use a dedicated read-only NAS export with an
appropriate identity mapping. Do not recursively change ownership of the shared
media library.

References: [systemd automounts](https://www.freedesktop.org/software/systemd/man/latest/systemd.automount.html),
[NFS hard-mount recovery](https://www.man7.org/linux/man-pages/man5/nfs.5.html).

## Create the container

Upload `nixos-plex-x86_64-linux.tar.xz` to the node's template storage (for the
default `local` storage: `/var/lib/vz/template/cache/`). The example below uses
CT ID `120`, bridge `vmbr0`, storage `local-lvm`, DHCP and a 32 GiB root disk.
Choose a free ID and adjust storage, bridge and disk size before running as root
on Proxmox. Large Plex metadata libraries may need a larger disk.

```sh
CTID=120
pct create "$CTID" local:vztmpl/nixos-plex-x86_64-linux.tar.xz \
  --arch amd64 --ostype nixos --hostname plex \
  --unprivileged 1 --features nesting=1,keyctl=1 \
  --cores 4 --memory 4096 --swap 512 \
  --rootfs local-lvm:32 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --nameserver 192.168.10.9 \
  --mp0 /mnt/media,mp=/mnt/media,ro=1,backup=0 \
  --onboot 0
```

Nesting supports systemd service isolation and the Nixpkgs Plex package's
Bubblewrap environment. The guest mounts no NFS filesystem itself.

Check which render device belongs to Intel on the node (`ls -l /dev/dri/by-path/`).
This configuration expects `/dev/dri/renderD128`. If Intel uses a different
render node, change `services.plex.accelerationDevices` in `default.nix` and
rebuild, and use that same device path below. On Proxmox with `dev0` support:

```sh
pct set "$CTID" --dev0 /dev/dri/renderD128,gid=303,mode=0660
```

`303` is the guest's NixOS `render` group, which Plex belongs to. The node must
already have a working Intel graphics driver; the guest cannot load its own
kernel driver. On older Proxmox releases without `dev0`, configure device
passthrough for that version before starting the container.

Require the NAS mount when the container starts, including after node reboots:

```sh
mkdir -p "/etc/systemd/system/pve-container@${CTID}.service.d"
cat > "/etc/systemd/system/pve-container@${CTID}.service.d/media.conf" <<'EOF'
[Unit]
RequiresMountsFor=/mnt/media
EOF
systemctl daemon-reload
pct start "$CTID"
pct exec "$CTID" -- /run/current-system/sw/bin/systemctl status plex --no-pager
pct exec "$CTID" -- /run/current-system/sw/bin/ip -4 addr show eth0
```

Open `http://CONTAINER_IP:32400/web`. Reserve its DHCP address. For first-time
setup from another subnet, tunnel through SSH:
`ssh -L 8888:127.0.0.1:32400 root@CONTAINER_IP`, then open
`http://localhost:8888/web`.

Inside the guest, check media and GPU access as Plex:

```sh
su -s /run/current-system/sw/bin/bash plex -c 'ls /media; ls /mnt/media'
su -s /run/current-system/sw/bin/bash plex -c 'vainfo --display drm --device /dev/dri/renderD128'
journalctl -u plex -n 50 --no-pager
```

Enable hardware acceleration in Plex's transcoder settings (requires an eligible
Plex subscription), force a video transcode, and confirm `(hw)` in the Plex
dashboard. Only after setup or migration succeeds, run `pct set "$CTID" --onboot 1`
on Proxmox. The media bind mount is excluded from LXC backups; back it up on the NAS.

## Existing Docker server: later migration

Source configuration: sibling repo `docker/plex/docker-compose.yaml`, using
`plexinc/pms-docker`, a named `/config` volume, a disposable `/transcode` volume
and host `/volume1/media` mounted at `/media`. The new guest preserves `/media`
as a symlink to `/mnt/media`, keeping existing library paths valid.

At cutover:

1. Check the running Docker Plex version against the template's version:
   `nix eval --raw path:.#nixosConfigurations.plex.config.services.plex.package.version`.
   The destination must be at least as new; update the lock/package before
   importing a database created by a newer server.
2. Disable Plex's automatic trash emptying until media access is verified.
   Locate the actual config volume using the running container's mount metadata;
   do not guess its Compose-prefixed volume name. Stop Docker Plex and back up
   its complete `/config` volume before copying. Keep the original volume intact.
3. Stop `plex-update.timer` and `plex.service` in the LXC. Copy the contents of Docker's
   `/config/Library/Application Support/Plex Media Server/` into
   `/var/lib/plex/Plex Media Server/`. Preserve `Preferences.xml`, the database,
   metadata and artwork, then set ownership of `/var/lib/plex` to `plex:plex`
   **inside the guest**. Do not copy Docker's outer `/config` directory here.
4. Start Plex in the LXC and check server identity, libraries, watched status,
   media reads, remote access and a hardware transcode before enabling autostart.
   Update any port forwarding or proxy target for the new container address.
   Keep Docker Plex stopped while the migrated server is running. Resume
   `plex-update.timer` after validation.

The migration is not performed by the template build. No old claim token is
reused. Avoid claiming a fresh server before importing the existing server data.
For rollback, stop the LXC's Plex service and restart the original Docker server
with its untouched volume; changes made after cutover will not be in that volume.

## Claim or reclaim the server

Normal updates and reboots do not require a claim code. The migrated
`Preferences.xml` preserves the server identity and account token; include it
when backing up `/var/lib/plex`.

Only if Plex becomes unclaimed:

1. Connect with `ssh root@192.168.10.30`.
2. Sign in at [plex.tv/claim](https://plex.tv/claim/) and copy a fresh code.
   Use it within four minutes.
3. Run this in the LXC's Bash shell and paste the code at the hidden prompt:

   ```bash
   read -rsp "Claim code: " plex_claim; echo
   curl -fsS -X POST -o /dev/null \
     "http://127.0.0.1:32400/myplex/claim?token=$plex_claim"
   unset plex_claim
   ```

The request runs locally and suppresses the account response. The code is not
saved in shell history. Never commit claim codes or account tokens to Git, and
do not delete `Preferences.xml` to obtain a new code.

See [Plex's manual claim procedure](https://forums.plex.tv/t/cannot-claim-server/724877).

## Remote access

The router forwards public TCP port `32400` to `192.168.10.30:32400`. In Plex's
**Settings → Remote Access**, enable **Manually specify public port**, enter
`32400`, and apply/retry. The router rule and Plex's public port must match.
Confirm external playback from a phone with Wi-Fi disabled.

## Updates

GitHub's standard Linux runner builds the complete Plex system after each push
to `main`, signs its Nix store closure and publishes a `plex-COMMIT` prerelease
containing `cache.tar` and `update.json`. Relevant pull requests build the template
without publishing updates. Manual runs on `main` also produce a downloadable
initial template. The repository is public, so standard runner execution is free.

The LXC checks `main` and waits until that exact commit's release is available.
It downloads the cache, verifies its checksum and Nix signatures, imports the
already-built system, and switches to it. It never evaluates the flake or compiles
updates. If `main` advances during download, it waits for the newer build. Failed
activation or a failed Plex health check restores the previous NixOS system.
The failed commit is skipped until a newer commit is published (to retry it,
remove `/var/lib/plex-update/failed-revision` and start the updater again);
this does not roll back Plex's database, so retain backups before package upgrades.
No SSH access from GitHub, local runner or GitHub credentials in the LXC are needed.

The signing public key is in `cache-public-key`. The private key is stored as the
repository Actions secret `PLEX_CACHE_SIGNING_KEY`; it is never included in the
template or releases. A backup is stored on this Mac under
`~/.config/homelab-nix/plex-cache/signing-key`. Preserve it when moving CI. The
publisher checks that its key matches the committed public key before signing.

Push this configuration before deployment so the workflow can publish the first
update. Merge checked changes to `main` to deploy; no new container is created.

To check immediately, run inside the guest as root:

```sh
systemctl start plex-update.service
journalctl -u plex-update.service -n 30 --no-pager
```

Pause updates with `systemctl stop plex-update.timer`, for example during
migration, and resume with `systemctl start plex-update.timer`. Wait for any
running `plex-update.service` to finish before copying the database. Plex may restart
when its package or service changes. Update `flake.lock` in the repo to update
Plex and NixOS; the existing weekly host-package Dependabot PR covers this pin.
Rebuild the template for future containers; existing containers update in place.
Keep `system.stateVersion` unchanged.

References: [NixOS Proxmox module](https://github.com/NixOS/nixpkgs/blob/08d3a97586f6b6343b3b5e799980773629432610/nixos/modules/virtualisation/proxmox-lxc.nix),
[Proxmox container options](https://pve.proxmox.com/pve-docs/pct.conf.5.html),
[Plex migration guide](https://support.plex.tv/articles/201370363-move-an-install-to-another-system/),
[Plex hardware transcoding](https://support.plex.tv/articles/115002178853-using-hardware-accelerated-streaming/).
