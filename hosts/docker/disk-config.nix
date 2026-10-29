{ config, ... }:
{
  # Disko manages ONLY the OS disk. Container storage must never be added here.
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
  # Use the existing data filesystem at /srv.
  fileSystems."/srv" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
    autoFormat = false;
  };

  # Reject accidental future changes that put persistent data under Disko.
  assertions = [
    {
      assertion = builtins.attrNames config.disko.devices.disk == [ "system" ];
      message = "Container host: Disko may manage only the OS disk; keep container data outside Disko.";
    }
    {
      assertion = !config.fileSystems."/srv".autoFormat;
      message = "Container host: automatic formatting of container storage is forbidden.";
    }
    {
      assertion = config.disko.devices.disk.system.device != config.fileSystems."/srv".device;
      message = "Container host: the OS and container data disk must be different devices.";
    }
  ];
}
