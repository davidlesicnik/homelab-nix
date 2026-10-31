{ config, ... }:
{
  imports = [
    ../../modules/nixos/common.nix
    ../../modules/nixos/gitops.nix
    ../../modules/nixos/secrets.nix
    ../../modules/nixos/beszel-agent.nix
    ../../modules/nixos/containers.nix
    ../../stacks/caddy
    ../../stacks/adguard
    ../../stacks/authelia
    ../../stacks/ha-phone
    ../../stacks/ha-tablet
    ../../stacks/ddns-updater
    ../../stacks/kiosk
    ../../stacks/beszel
    ../../stacks/dockhand
    ../../stacks/qbittorrent
    ../../stacks/litara
    ../../stacks/sabnzbd
    ../../stacks/prowlarr
    ../../stacks/sonarr
    ../../stacks/radarr
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  sops.secrets."beszel-agent/token".sopsFile = ./secrets.yaml;

  networking = {
    hostName = "podman";
    useDHCP = false;
    interfaces.ens18 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.10.20";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.10.1";
      interface = "ens18";
    };
    nameservers = [ "192.168.10.9" ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7iGgfuh/s+vJWkwMcOWPaznY+NaBlwO/dzF62fFQzu david.lesicnik@eventim.com"
  ];

  users.users.containers.openssh.authorizedKeys.keys =
    config.users.users.root.openssh.authorizedKeys.keys;

  fileSystems."/mnt/media" = {
    device = "192.168.10.9:/volume1/media";
    fsType = "nfs";
    options = [
      "_netdev"
      "nofail"
      "x-systemd.automount"
      "x-systemd.mount-timeout=30s"
    ];
  };

  # Keep this at the release used for the initial installation.
  system.stateVersion = "26.05";
}
