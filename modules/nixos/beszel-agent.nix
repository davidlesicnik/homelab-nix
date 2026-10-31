{ config, lib, pkgs, ... }:
let
  podmanHost = config.virtualisation.podman.enable;
  agentUser = if podmanHost then "containers" else "beszel-agent";
in
{
  # Each host declares its own encrypted sopsFile.
  sops.secrets."beszel-agent/token" = {
    key = "token";
    owner = agentUser;
    mode = "0400";
    restartUnits = [ "beszel-agent.service" ];
  };

  services.beszel.agent = {
    enable = true;
    package = pkgs.callPackage ./beszel-agent-package.nix { };
    environment = {
      HUB_URL = "https://beszel.lesicnik.eu";
      KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAD2Wguk9ncOA4MN7xEq37FT2YLLk+gh84btqoVL6TMb";
      TOKEN_FILE = config.sops.secrets."beszel-agent/token".path;
      DISABLE_SSH = "true";
      DATA_DIR = "/var/lib/beszel-agent";
      # Container image updates are already managed by this repository.
      DOCKER_IMAGE_CHECK = "false";
    } // lib.optionalAttrs podmanHost {
      DOCKER_HOST = "unix:///run/user/1000/podman/podman.sock";
      EXTRA_FILESYSTEMS = "/srv";
      # The agent runs as the rootless Podman user to access its private socket.
      SKIP_SYSTEMD = true;
    };
  };

  systemd.services.beszel-agent = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    serviceConfig = {
      User = lib.mkForce agentUser;
      DynamicUser = lib.mkForce (!podmanHost);
      # Preserve the Podman user's socket permissions; also works inside an LXC.
      PrivateUsers = lib.mkForce false;
      StateDirectory = "beszel-agent";
    };
  };
}
