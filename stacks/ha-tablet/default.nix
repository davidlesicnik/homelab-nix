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
    # Unknown paths return index.html: check real content and the mounted config.
    healthcheck.command = [
      "/bin/sh"
      "-ec"
      ''
        curl -fsS --max-time 3 http://127.0.0.1/ | grep -qi '<html'
        curl -fsS --max-time 3 http://127.0.0.1/config.json | cmp -s /usr/share/nginx/html/config.json -
      ''
    ];
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
