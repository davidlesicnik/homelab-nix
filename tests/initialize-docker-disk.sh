#!/usr/bin/env bash
set -euo pipefail

# Exercise the destructive-operation guards with mocked tools only.
# mkfs.ext4 is always replaced; these tests never open or format a device.
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
test_device=/dev/disk/by-id/test-empty-disk

for scenario in blank existing-label filesystem partition-table partitioned mounted swap not-disk inspection-error declined no-input changed; do
  marker="$test_dir/$scenario.formatted"
  counter="$test_dir/$scenario.inspections"
  confirmation="INITIALIZE $test_device"
  [[ "$scenario" != declined ]] || confirmation=no
  [[ "$scenario" != no-input ]] || confirmation=''

  if (
    source "$repo_root/scripts/initialize-docker-disk.sh"

    docker_data_exists() { [[ "$scenario" == existing-label ]]; }

    lsblk() {
      local output=''
      while [[ $# -gt 0 ]]; do
        if [[ "$1" == --output ]]; then
          output="$2"
          break
        fi
        shift
      done
      case "$output" in
        TYPE)
          if [[ "$scenario" == not-disk ]]; then printf 'part\n'; else printf 'disk\n'; fi
          ;;
        NAME)
          if [[ "$scenario" == partitioned ]]; then printf 'sdb\nsdb1\n'; else printf 'sdb\n'; fi
          ;;
        MOUNTPOINTS)
          case "$scenario" in
            mounted) printf '/mnt/data\n' ;;
            swap) printf '[SWAP]\n' ;;
          esac
          ;;
        NAME,SIZE,MODEL,SERIAL) printf 'test disk\n' ;;
        *) return 1 ;;
      esac
      return 0
    }

    wipefs() {
      case "$scenario" in
        filesystem) printf 'ext4\n' ;;
        partition-table) printf 'gpt\n' ;;
        inspection-error) return 1 ;;
        changed)
          if [[ -e "$counter" ]]; then printf 'ext4\n'; else touch "$counter"; fi
          ;;
      esac
      return 0
    }

    mkfs.ext4() {
      printf '%s\n' "$*" > "$marker"
    }

    if [[ "$scenario" == no-input ]]; then
      initialize_disk "$test_device" < /dev/null
    else
      initialize_disk "$test_device" <<< "$confirmation"
    fi
  ) > "$test_dir/$scenario.log" 2>&1; then
    [[ "$scenario" == blank ]] || { cat "$test_dir/$scenario.log"; exit 1; }
    [[ -f "$marker" ]] || { printf 'Initializer did not run for blank disk\n'; exit 1; }
    [[ "$(cat "$marker")" == "-L docker-data $test_device" ]] || exit 1
  else
    [[ "$scenario" != blank ]] || { cat "$test_dir/$scenario.log"; exit 1; }
    [[ ! -e "$marker" ]] || { printf 'Formatter ran for unsafe case: %s\n' "$scenario"; exit 1; }
  fi
  printf 'PASS: %s\n' "$scenario"
done

for unsupported_device in /dev/sdb /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0; do
  if bash "$repo_root/scripts/initialize-docker-disk.sh" "$unsupported_device" > "$test_dir/arguments.log" 2>&1; then
    printf 'Arbitrary device argument was accepted\n'
    exit 1
  fi
done
printf 'PASS: arbitrary device arguments rejected\n'
