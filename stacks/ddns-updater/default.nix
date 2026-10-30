{ config, lib, ... }:
let
  ddnsConfig = import ./config.nix {
    cloudflareApiToken = config.sops.placeholder."ddns-updater/cloudflare_api_token";
  };
in
{
  sops.secrets."ddns-updater/cloudflare_api_token" = {
    sopsFile = ./secrets.yaml;
    key = "cloudflare_api_token";
  };
  sops.templates."ddns-updater.env" = {
    # CONFIG takes precedence over config.json and is read on container startup.
    content = ''
      CONFIG=${builtins.toJSON ddnsConfig}
    '';
    owner = "containers";
    group = "containers";
    mode = "0400";
    restartUnits = [ "podman-ddns-updater.service" ];
  };

  virtualisation.oci-containers.containers.ddns-updater = {
    image = "docker.io/qmcgaw/ddns-updater:2.10.0";
    networks = [ "proxy" ];
    labels."dockhand.url" = "https://ddns.lesicnik.eu";
    environment.TZ = "Europe/Ljubljana";
    environmentFiles = [ config.sops.templates."ddns-updater.env".path ];
    volumes = [ "ddns-updater-data:/updater/data" ];
    extraOptions = [ "--dns=8.8.8.8" ];
  };

  systemd.services.podman-ddns-updater = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    # The runtime env-file path is stable. Track the generated template's store
    # path too, so adding/removing/editing records recreates the container.
    restartTriggers = [ config.sops.templates."ddns-updater.env".file ];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
