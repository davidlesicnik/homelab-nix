{ config, lib, ... }:
{
  sops.secrets."your-mail-mcp/accounts_json" = {
    sopsFile = ./secrets.yaml;
    key = "accounts_json";
    owner = "containers";
    group = "containers";
    mode = "0400";
    restartUnits = [ "podman-your-mail-mcp.service" ];
  };
  sops.secrets."your-mail-mcp/oauth_passphrase" = {
    sopsFile = ./secrets.yaml;
    key = "oauth_passphrase";
  };
  sops.templates."your-mail-mcp.env" = {
    content = ''
      OAUTH_PASSPHRASE=${config.sops.placeholder."your-mail-mcp/oauth_passphrase"}
    '';
    owner = "containers";
    group = "containers";
    mode = "0400";
    restartUnits = [ "podman-your-mail-mcp.service" ];
  };

  virtualisation.oci-containers.containers.your-mail-mcp = {
    imageManifest = ./Dockerfile;
    cmd = [ "serve" ];
    networks = [ "proxy" ];
    # Map the image's UID to the host's containers user for private secret mounts.
    extraOptions = [ "--userns=keep-id:uid=1000,gid=1000" ];
    environment = {
      PUBLIC_URL = "https://mail-mcp.lesicnik.eu";
      SYNC_INTERVAL = "10m";
      SYNC_TIMEOUT = "1h";
    };
    environmentFiles = [ config.sops.templates."your-mail-mcp.env".path ];
    volumes = [
      "${config.sops.secrets."your-mail-mcp/accounts_json".path}:/config/accounts.json:ro"
      "your-mail-mcp-mail:/mail"
      "your-mail-mcp-index:/index"
    ];
    # Discovery confirms HTTP/OAuth startup; mailbox sync health is in MCP status.
    healthcheck.command = [
      "/bin/sh"
      "-ec"
      ''
        /usr/bin/w3m -dump_source http://127.0.0.1:8080/.well-known/oauth-protected-resource/mcp | /usr/bin/grep -Fq '"resource":"https://mail-mcp.lesicnik.eu/mcp"'
      ''
    ];
  };

  systemd.services.podman-your-mail-mcp = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
