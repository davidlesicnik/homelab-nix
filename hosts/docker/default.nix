{ ... }:
{
  imports = [
    ../../modules/nixos/common.nix
    # Enable GitOps after the deployment workflow is ready:
    # ../../modules/nixos/gitops.nix
    ../../modules/nixos/docker.nix
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "docker";
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

  # Keep this at the release used for the initial installation.
  system.stateVersion = "26.05";
}
