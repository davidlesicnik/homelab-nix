{ lib, pkgs, ... }:
{
  virtualisation.oci-containers.containers.sabnzbd = {
    # Keep the exact NAS image while moving the existing configuration and data.
    image = "lscr.io/linuxserver/sabnzbd@sha256:3ac1c9ea03bafa2588dd8acdcb809857bae305e71d2d90e11d689c78076a9c01";
    networks = [ "proxy" ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "Europe/Ljubljana";
    };
    # Keep the application UID/GID equal to the NAS identity for NFS access,
    # while allowing the image's init process to run as container root.
    user = "0:0";
    extraOptions = [ "--userns=keep-id:uid=1000,gid=1000" ];
    volumes = [
      "/srv/sabnzbd/config:/config"
      "/mnt/media:/media"
    ];
    labels."dockhand.url" = "https://usenet.lesicnik.eu";
  };

  systemd.services.podman-sabnzbd = {
    requires = [ "mnt-media.mount" ];
    after = [ "mnt-media.mount" ];
    bindsTo = [ "mnt-media.mount" ];
    unitConfig.ConditionPathExists = "/srv/sabnzbd/.migration-complete";
    # Refuse to use the empty local directory if the NFS mount is unavailable.
    preStart = lib.mkBefore ''
      ${pkgs.util-linux}/bin/findmnt --noheadings --types nfs,nfs4 --mountpoint /mnt/media >/dev/null
    '';
    serviceConfig.Restart = lib.mkForce "always";
  };
}
