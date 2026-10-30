{ lib, ... }:
{
  virtualisation.oci-containers.containers.adguardhome = {
    imageManifest = ./Dockerfile;
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
    allowedTCPPorts = [ 53 3000 3001 ];
    allowedUDPPorts = [ 53 ];
  };
}
