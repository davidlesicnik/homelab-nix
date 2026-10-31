{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/virtualisation/proxmox-lxc.nix"
    ../../modules/nixos/common.nix
    ./updates.nix
  ];

  environment.etc."plex-build-revision".text =
    if config.system.configurationRevision == null then "unpublished\n"
    else "${config.system.configurationRevision}\n";

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "plexmediaserver" ];

  # Proxmox supplies the hostname, network configuration and DNS.
  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
    manageHostName = false;
  };
  image.baseName = "nixos-plex-x86_64-linux";

  services.plex = {
    enable = true;
    package = pkgs.callPackage ./package.nix { };
    openFirewall = true;
    dataDir = "/var/lib/plex";
    accelerationDevices = [ "/dev/dri/renderD128" ];
  };

  # Stable IDs for permissions on Proxmox's read-only NAS bind mount.
  users.users.plex = {
    uid = lib.mkForce 1000;
    isSystemUser = true;
    extraGroups = [ "video" "render" ];
  };
  users.groups.plex.gid = lib.mkForce 1000;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver intel-vaapi-driver vpl-gpu-rt ];
  };
  environment.systemPackages = [ pkgs.libva-utils ];

  systemd.tmpfiles.rules = [
    "d /mnt/media 0755 root root -"
    # The existing Docker Plex library uses /media, so preserve that path.
    "L /media - - - - /mnt/media"
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7iGgfuh/s+vJWkwMcOWPaznY+NaBlwO/dzF62fFQzu david.lesicnik@eventim.com"
  ];

  # Keep this at the release used for the initial installation.
  system.stateVersion = "26.05";
}
