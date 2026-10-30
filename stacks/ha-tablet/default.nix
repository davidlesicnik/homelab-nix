{ config, lib, ... }:
{
  sops.secrets."ha-tablet/config_json" = {
    sopsFile = ./secrets.yaml;
    key = "config_json";
    owner = "containers";
    group = "containers";
    # Nginx workers run as a separate UID inside the rootless container.
    mode = "0444";
    restartUnits = [ "podman-ha-tablet.service" ];
  };

  virtualisation.oci-containers.containers.ha-tablet = {
    imageManifest = ./Dockerfile;
    networks = [ "proxy" ];
    volumes = [
      "${config.sops.secrets."ha-tablet/config_json".path}:/usr/share/nginx/html/config.json:ro"
    ];
    labels."dockhand.url" = "https://tablet.lesicnik.eu";
  };

  systemd.services.podman-ha-tablet = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
