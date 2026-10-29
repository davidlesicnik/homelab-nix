{
  config,
  lib,
  pkgs,
  ...
}:
let
  image = pkgs.callPackage ./image.nix { };
  caddyConfig = pkgs.callPackage ./config.nix { };
in
{
  sops.secrets."caddy/cloudflare_api_token" = {
    sopsFile = ./secrets.yaml;
    key = "cloudflare_api_token";
  };
  sops.templates."caddy.env" = {
    content = ''
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder."caddy/cloudflare_api_token"}
    '';
    owner = "containers";
    group = "containers";
    mode = "0400";
    restartUnits = [ "podman-caddy.service" ];
  };

  virtualisation.oci-containers.containers.caddy = {
    image = "${image.imageName}:${image.imageTag}";
    imageFile = image;
    networks = [ "proxy" ];
    ports = [
      "80:80"
      "443:443"
      "443:443/udp"
    ];
    environmentFiles = [ config.sops.templates."caddy.env".path ];
    volumes = [
      "${caddyConfig}:/etc/caddy:ro"
      "caddy-data:/data"
      "caddy-config:/config"
    ];
  };

  systemd.services.podman-caddy = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    # Includes every imported site file, so config-only commits restart Caddy.
    restartTriggers = [ caddyConfig ];
    serviceConfig.Restart = lib.mkForce "always";
  };

  # Permit the rootless port forwarder to bind Caddy's standard HTTP(S) ports.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;
  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
  };
}
