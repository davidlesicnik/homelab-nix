{ lib, ... }:
{
  virtualisation.oci-containers.containers.adguardhome = {
    imageManifest = ./Dockerfile;
    # Exercise DNS as well as the admin HTTP listener, without credentials.
    healthcheck.command = [
      "/bin/sh"
      "-ec"
      ''
        wget -q -T 3 -O /dev/null http://127.0.0.1:3001/login.html
        nslookup example.com 192.168.10.20 >/dev/null
      ''
    ];
    # Preserve DNS client addresses instead of using rootless port forwarding.
    extraOptions = [ "--network=host" ];
    volumes = [
      "adguard-work:/opt/adguardhome/work"
      "adguard-conf:/opt/adguardhome/conf"
    ];
    labels."dockhand.url" = "https://adguard.lesicnik.eu";
  };

  systemd.services.podman-adguardhome.serviceConfig.Restart = lib.mkForce "always";

  # Host networking still runs as the unprivileged containers user.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 53;
  networking.firewall.interfaces.ens18 = {
    # Setup is complete; Caddy reaches admin port 3001 locally.
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}
