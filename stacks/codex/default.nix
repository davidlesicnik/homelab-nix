{ pkgs, lib, ... }:
let
  image = pkgs.callPackage ./image.nix { };
in
{
  virtualisation.oci-containers.containers.codex = {
    image = "${image.imageName}:${image.imageTag}";
    imageFile = image;
    volumes = [
      "codex-home:/home/codex"
      "codex-repos:/workspace"
    ];
    extraOptions = [
      "--hostname=homelab-codex"
      "--userns=keep-id:uid=1000,gid=1000"
      "--init"
    ];
    healthcheck.command = [ "codex" "app-server" "daemon" "version" ];
  };

  systemd.services.podman-codex.serviceConfig.Restart = lib.mkForce "always";
}
