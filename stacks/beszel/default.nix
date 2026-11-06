{ lib, ... }:
{
  virtualisation.oci-containers.containers.beszel = {
    imageManifest = ./Dockerfile;
    healthcheck.command = [
      "/beszel"
      "health"
      "--url"
      "http://127.0.0.1:8090"
    ];
    networks = [ "proxy" ];
    labels."dockhand.url" = "https://beszel.lesicnik.eu";
    environment = {
      BESZEL_HUB_APP_URL = "https://beszel.lesicnik.eu";
      BESZEL_HUB_USER_CREATION = "true";
      DISABLE_PASSWORD_AUTH = "true";
    };
    volumes = [ "beszel-data:/beszel_data" ];
  };

  systemd.services.podman-beszel.serviceConfig.Restart = lib.mkForce "always";
}
