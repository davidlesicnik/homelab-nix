{ lib, ... }:
{
  virtualisation.oci-containers.containers.prowlarr = {
    # Preserve the exact running NAS image during the data migration.
    image = "ghcr.io/hotio/prowlarr@sha256:8c5ebfedf7ba82af100914993ba1f2942b1809ab1d18b85e4833362a292c7c5e";
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
