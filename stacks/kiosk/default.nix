{ config, lib, ... }:
{
  sops.secrets."kiosk/immich_api_key" = {
    sopsFile = ./secrets.yaml;
    key = "immich_api_key";
  };
  sops.templates."kiosk.env" = {
    content = ''
      KIOSK_IMMICH_API_KEY=${config.sops.placeholder."kiosk/immich_api_key"}
    '';
    owner = "containers";
    group = "containers";
    mode = "0400";
    restartUnits = [ "podman-immich-kiosk.service" ];
  };

  virtualisation.oci-containers.containers.immich-kiosk = {
    image = "ghcr.io/damongolding/immich-kiosk:0.45.2";
    networks = [ "proxy" ];
    # Changes to these settings regenerate the service and recreate the container.
    environment = import ./config.nix;
    environmentFiles = [ config.sops.templates."kiosk.env".path ];
    volumes = [ "kiosk-config:/config" ];
    extraOptions = [
      "--tty"
      # Match Compose: the distroless image has no shell for its healthcheck.
      "--no-healthcheck"
    ];
  };

  systemd.services.podman-immich-kiosk = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
