{ lib, ... }:
{
  virtualisation.oci-containers.containers.beszel = {
    image = "docker.io/henrygd/beszel:0.21.1";
    networks = [ "proxy" ];
    environment = {
      BESZEL_HUB_APP_URL = "https://beszel.lesicnik.eu";
      BESZEL_HUB_USER_CREATION = "true";
    };
    volumes = [ "beszel-data:/beszel_data" ];
  };

  systemd.services.podman-beszel.serviceConfig.Restart = lib.mkForce "always";
}
