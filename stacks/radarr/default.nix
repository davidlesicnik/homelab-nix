{ lib, pkgs, ... }:
{
  virtualisation.oci-containers.containers.radarr = {
    # Preserve the exact NAS image while moving the existing database.
    image = "ghcr.io/hotio/radarr@sha256:571098eb98381660a1ce48500187a660d67ca1362fb8e6b5903f2d0e4ddde620";
    networks = [ "proxy" ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
      TZ = "Europe/Vienna";
    };
    user = "0:0";
    extraOptions = [ "--userns=keep-id:uid=1000,gid=1000" ];
    volumes = [
      "/srv/radarr/config:/config"
      "/mnt/media/movies:/data"
      "/mnt/media/download:/downloads"
    ];
    labels."dockhand.url" = "https://radarr.lesicnik.eu";
  };

  systemd.services.podman-radarr = {
    requires = [ "mnt-media.mount" ];
    after = [ "mnt-media.mount" ];
    bindsTo = [ "mnt-media.mount" ];
    unitConfig.ConditionPathExists = "/srv/radarr/.migration-complete";
    preStart = lib.mkBefore ''
      ${pkgs.util-linux}/bin/findmnt --noheadings --types nfs,nfs4 --mountpoint /mnt/media >/dev/null
    '';
    serviceConfig.Restart = lib.mkForce "always";
  };
}
