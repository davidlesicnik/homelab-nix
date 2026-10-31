{ config, lib, ... }:
{
  sops.secrets."ha-phone/config_json" = {
    sopsFile = ./secrets.yaml;
    key = "config_json";
    owner = "containers";
    group = "containers";
    # Nginx workers run as a separate UID inside the rootless container.
    mode = "0444";
    restartUnits = [ "podman-ha-phone.service" ];
  };

  virtualisation.oci-containers.containers.ha-phone = {
    imageManifest = ./Dockerfile;
    networks = [ "proxy" ];
    volumes = [
      "${config.sops.secrets."ha-phone/config_json".path}:/usr/share/nginx/html/config.json:ro"
    ];
    labels."dockhand.url" = "https://phone.lesicnik.eu";
  };

  systemd.services.podman-ha-phone = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
