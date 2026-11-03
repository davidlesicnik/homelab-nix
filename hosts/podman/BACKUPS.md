# Podman backups

Restic runs nightly at **01:00 Europe/Ljubljana**. A missed run catches up after
boot. The encrypted repository is `sftp:restic@192.168.10.9:/docker_restic`.

## Scope and consistency

The configuration derives sources from all declared containers: named volumes
and bind mounts below `/srv`. It also saves migration markers and a manifest
containing the Git revision, image versions, and mount mappings. Image layers,
Podman runtime metadata, old migration copies, and `/mnt/media` are excluded. This does
not back up Plex, Home Assistant, Immich, or other services on separate hosts.

Affected system services stop in dependency order while rsync makes a local
copy at `/srv/.restic-podman`. PostgreSQL is shut down too: these are complete
cold database backups, restored with the same PostgreSQL major version. SQLite
databases, attachments, and configuration are copied together. Services resume
before uploading, pruning, or checking the NAS. Expect a nightly interruption
to these apps, including AdGuard DNS and Caddy; the initial copy takes longer.
The persistent staging copy needs space roughly equal to the selected data.

Preparation refuses missing source directories. Previously active services are
recorded durably before stopping; `finally` and systemd `ExecStopPost` both retry
recovery after failures. Services that were inactive stay inactive unless needed
as dependencies of active services. A host reboot starts enabled services as
usual. If restart fails, fix the cause and start the recorded units as described below.
Do not deploy container updates or manually start stopped containers during the
local copying phase.

## Credentials and retention

`hosts/podman/secrets.yaml` contains the existing dedicated SSH private key and a
random Restic password, encrypted for the administrator and host age identities.
NixOS decrypts them as root-only files under `/run/secrets/restic/`; neither goes
into the Nix store. The NAS Ed25519 host key is pinned in the backup module.

Retention: 14 daily, 8 weekly, 12 monthly, and 3 yearly snapshots. Pruning runs
only after a successful backup. Each run checks repository metadata and a random
5% of stored data, then restores and compares the manifest. This small restore
test does not replace periodically restoring an entire application.

Keep an independent copy of your workstation's SOPS age identity and save the
repository password in your password manager. Losing the password and all age
identities loses access to the backups. To retrieve it locally:

```sh
nix develop --command sops --decrypt --extract '["restic_password"]' hosts/podman/secrets.yaml
```

The NAS account currently has administrator rights. Restrict it to SFTP access
to this share when the NAS permits that without breaking public-key login, then
retest from the Podman host. A second offsite or immutable copy is still needed
for NAS failure or deletion using compromised backup credentials.

## Deploy and inspect

Merge the reviewed configuration into `main`; normal GitOps activates the timer.
The following commands run as root on the Podman host:

```sh
systemctl list-timers restic-backups-podman.timer
systemctl start restic-backups-podman.service
journalctl -u restic-backups-podman.service -n 100 --no-pager
cat /var/lib/restic-podman/last-success
restic-podman snapshots
```

Manual runs also stop applications briefly. A failed backup/check leaves the
unit failed and does not advance `last-success`; inspect this timestamp and
systemd failures in monitoring. No external notification destination is configured.
If services could not resume, inspect `/var/lib/restic-podman/stopped-services.json`,
fix their startup errors, and start just those units with `systemctl start`.
The next backup also retries this recovery before taking another copy.

## Restore

Restore to a separate directory first; never over running application data:

```sh
restic-podman snapshots
restic-podman restore SNAPSHOT_ID --target /srv/restic-restore --verify
```

The recovered tree is below
`/srv/restic-restore/srv/.restic-podman/`. Its `manifest.json` lists original
paths, volume mappings, images, and Git revision. Bind-mount data is under
`srv/<app>/`; named volume contents are under
`srv/podman/.local/share/containers/storage/volumes/<name>/_data/`.

1. Stop the affected application and its database with `systemctl stop`.
2. On a replacement host, restore the Git configuration and SOPS identity,
   preserve UID/GID and subordinate UID/GID mappings, and create the named volumes
   as `containers` before copying data. Keep the backup timer stopped until done.
3. Copy the selected data back as root with `rsync -aHAX --numeric-ids`, preserving
   ownership and migration markers. Restore the complete PostgreSQL volume and
   use the major version recorded in the manifest. Keep the previous data for
   rollback; avoid merging restored database files into an existing database.
4. Start database/application units, check Podman health and application data,
   then re-enable the backup timer. Remove the temporary restore after validation.

References: [Restic SFTP](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#sftp)
and [PostgreSQL cold backups](https://www.postgresql.org/docs/current/backup-file.html).
