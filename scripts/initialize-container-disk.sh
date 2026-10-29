#!/usr/bin/env bash
set -euo pipefail

# One-time bootstrap for a NEW, EMPTY disk. Never called by NixOS or GitOps.
# No force flags, signature removal, partition deletion, or reformat mode.
container_device=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1

fail() {
  printf 'Refusing to initialize: %s\n' "$*" >&2
  exit 1
}

filesystem_label_exists() {
  [[ -e "/dev/disk/by-label/$1" || -L "/dev/disk/by-label/$1" ]]
}

check_empty_disk() {
  local device="$1" disk_type nodes mounts signatures

  if filesystem_label_exists container-data || filesystem_label_exists docker-data; then
    fail 'a container-data or legacy docker-data filesystem already exists; mount it instead.'
  fi

  disk_type=$(lsblk --nodeps --noheadings --output TYPE "$device") || fail 'cannot inspect device type.'
  [[ "$disk_type" == disk ]] || fail 'the device is not a whole disk.'

  nodes=$(lsblk --list --noheadings --output NAME "$device") || fail 'cannot inspect partitions.'
  [[ -n "$nodes" && "$nodes" != *$'\n'* ]] || fail 'the disk has partitions or dependent devices.'

  mounts=$(lsblk --noheadings --output MOUNTPOINTS "$device") || fail 'cannot inspect mounts.'
  [[ ! "$mounts" =~ [^[:space:]] ]] || fail 'the disk is mounted or in use as swap.'

  signatures=$(wipefs --no-act --noheadings --output TYPE "$device") || fail 'cannot inspect disk signatures.'
  [[ -z "$signatures" ]] || fail 'the disk already contains a filesystem, partition table, or other signature.'
}

initialize_disk() {
  local device="$1" confirmation
  check_empty_disk "$device"
  lsblk --nodeps --output NAME,SIZE,MODEL,SERIAL "$device"
  printf '\nThis creates ext4 on the empty disk above.\nType INITIALIZE %s to continue: ' "$device"
  read -r confirmation || fail 'no confirmation was entered.'
  [[ "$confirmation" == "INITIALIZE $device" ]] || fail 'confirmation did not match.'

  # Recheck after confirmation. Existing storage is never reformatted.
  check_empty_disk "$device"
  mkfs.ext4 -L container-data "$device"
}

main() {
  [[ $# -eq 0 ]] || fail 'this initializer only supports the configured scsi1 disk; do not pass a device.'
  [[ "$EUID" -eq 0 ]] || fail 'run this script as root.'
  [[ -b "$container_device" ]] || fail 'the configured scsi1 disk does not exist or is not a block device.'
  initialize_disk "$container_device"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
