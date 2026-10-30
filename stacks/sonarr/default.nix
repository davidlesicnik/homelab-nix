{ lib, pkgs, ... }:
{
  virtualisation.oci-containers.containers.sonarr = {
    # Preserve the exact NAS image while moving the existing database.
    image = "ghcr.io/hotio/sonarr@sha256:1cf15fb504603e6784aa3be275019bbef9c46a4e4f3e575fe28d56ff30590823";
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
