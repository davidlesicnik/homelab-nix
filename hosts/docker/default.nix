{ ... }:
{
  imports = [
    ../../modules/nixos/common.nix
    ../../modules/nixos/gitops.nix
    ../../modules/nixos/docker.nix
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  networking.hostName = "docker";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7iGgfuh/s+vJWkwMcOWPaznY+NaBlwO/dzF62fFQzu david.lesicnik@eventim.com"
  ];

  # Keep this at the release used for the initial installation.
  system.stateVersion = "26.05";
}
