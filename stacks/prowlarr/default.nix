{ lib, ... }:
{
  virtualisation.oci-containers.containers.prowlarr = {
    imageManifest = ./Dockerfile;
    healthcheck.command = [
      "curl"
      "--fail"
      "--silent"
      "--show-error"
      "--max-time"
      "5"
      "--output"
      "/dev/null"
      "http://127.0.0.1:9696/ping"
    ];
    networks = [ "proxy" ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
      TZ = "Europe/Ljubljana";
    };
    user = "0:0";
    extraOptions = [ "--userns=keep-id:uid=1000,gid=1000" ];
    volumes = [ "/srv/prowlarr/config:/config" ];
    labels."dockhand.url" = "https://prowlarr.lesicnik.eu";
  };

  systemd.services.podman-prowlarr = {
    # Never initialize a fresh database in place of the migrated configuration.
    unitConfig.ConditionPathExists = "/srv/prowlarr/.migration-complete";
    serviceConfig.Restart = lib.mkForce "always";
  };
}
