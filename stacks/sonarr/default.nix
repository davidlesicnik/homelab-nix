{ lib, pkgs, ... }:
{
  virtualisation.oci-containers.containers.sonarr = {
    image = "ghcr.io/hotio/sonarr:release-4.0.20.3014";
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
      "/srv/sonarr/config:/config"
      "/mnt/media/tv:/data"
      "/mnt/media/download/tv:/downloads"
    ];
    labels."dockhand.url" = "https://sonarr.lesicnik.eu";
  };

  systemd.services.podman-sonarr = {
    requires = [ "mnt-media.mount" ];
    after = [ "mnt-media.mount" ];
    bindsTo = [ "mnt-media.mount" ];
    unitConfig.ConditionPathExists = "/srv/sonarr/.migration-complete";
    preStart = lib.mkBefore ''
      ${pkgs.util-linux}/bin/findmnt --noheadings --types nfs,nfs4 --mountpoint /mnt/media >/dev/null
    '';
    serviceConfig.Restart = lib.mkForce "always";
  };
}
