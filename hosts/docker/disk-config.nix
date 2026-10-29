{ config, ... }:
{
  # Disko manages ONLY the OS disk. Docker storage must never be added here.
  # Fixed Proxmox SCSI identities prevent /dev/sdX enumeration changes.
  disko.devices.disk = {
    system = {
      type = "disk";
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0"; # 32 GiB OS disk
      destroy = false;
      content = {
        type = "gpt";
        partitions = {
          bios = {
            size = "1M";
            type = "EF02";
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };

  # Mount an existing filesystem; NixOS must never create or format this disk.
  fileSystems."/var/lib/docker" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
    autoFormat = false;
  };

  # Reject accidental future changes that put persistent data under Disko.
  assertions = [
    {
      assertion = builtins.attrNames config.disko.devices.disk == [ "system" ];
      message = "Docker host: Disko may manage only the OS disk; keep Docker data outside Disko.";
    }
    {
      assertion = !config.fileSystems."/var/lib/docker".autoFormat;
      message = "Docker host: automatic formatting of Docker storage is forbidden.";
    }
    {
      assertion = config.disko.devices.disk.system.device != config.fileSystems."/var/lib/docker".device;
      message = "Docker host: the OS and Docker data disk must be different devices.";
    }
  ];
}
