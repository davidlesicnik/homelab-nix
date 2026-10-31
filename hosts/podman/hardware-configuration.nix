{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # QEMU/Proxmox VM with SCSI/SATA disks and legacy BIOS (SeaBIOS).
  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "sr_mod"
  ];
  boot.loader.grub.enable = true;
  # Disko derives grub.devices from the BIOS boot partition on the OS disk.

  services.qemuGuest.enable = true;
}
