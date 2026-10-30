{ lib, pkgs, ... }:
{
  virtualisation.oci-containers.containers.qbittorrent = {
    imageManifest = ./Dockerfile;
    networks = [ "proxy" ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "Europe/Vienna";
      WEBUI_PORT = "1234";
      TORRENTING_PORT = "30054";
    };
    user = "0:0";
    extraOptions = [ "--userns=keep-id:uid=1000,gid=1000" ];
    volumes = [
      "/srv/qbittorrent/config:/config"
      "/mnt/media:/media"
    ];
    ports = [ "30054:30054" "30054:30054/udp" ];
    labels."dockhand.url" = "https://torrent.lesicnik.eu";
  };

  systemd.services.podman-qbittorrent = {
    requires = [ "mnt-media.mount" ];
    after = [ "mnt-media.mount" ];
    bindsTo = [ "mnt-media.mount" ];
    unitConfig.ConditionPathExists = "/srv/qbittorrent/.migration-complete";
    preStart = lib.mkBefore ''
      ${pkgs.util-linux}/bin/findmnt --noheadings --types nfs,nfs4 --mountpoint /mnt/media >/dev/null
    '';
    serviceConfig.Restart = lib.mkForce "always";
  };
  networking.firewall = {
    allowedTCPPorts = [ 30054 ];
    allowedUDPPorts = [ 30054 ];
  };
}
