{ config, lib, ... }:
let
  secretNames = [
    "reset_password_jwt_secret_json"
    "session_secret_json"
    "storage_encryption_key_json"
    "oidc_hmac_secret_json"
    "oidc_signing_key_0_json"
    "oidc_client_bootstrap_client_json"
    "oidc_client_lubelogger_json"
    "oidc_client_home_assistant_json"
    "oidc_client_proxmox_ve_json"
    "oidc_client_proxmox_backup_server_json"
    "oidc_client_beszel_json"
    "oidc_client_tududi_json"
  ];
  placeholder = name: config.sops.placeholder."authelia/${name}";
  settings = import ./config.nix { secret = placeholder; };
  # Each encrypted setting is a JSON value, including its quotes. Substitute
  # outside JSON strings so multiline PEM keys and special characters survive.
  configuration = builtins.replaceStrings
    (map (name: builtins.toJSON (placeholder name)) secretNames)
    (map placeholder secretNames)
    (builtins.toJSON settings);
in
{
  sops.secrets = lib.genAttrs (map (name: "authelia/${name}") (secretNames ++ [ "users_database" ])) (name: {
    sopsFile = ./secrets.yaml;
    key = lib.removePrefix "authelia/" name;
  }) // {
    "authelia/users_database" = {
      sopsFile = ./secrets.yaml;
      key = "users_database";
      owner = "containers";
      group = "containers";
      mode = "0400";
      restartUnits = [ "podman-authelia.service" ];
    };
  };

  sops.templates."authelia-configuration.yml" = {
    # JSON is valid YAML and avoids indentation-sensitive secret substitution.
    content = configuration;
    owner = "containers";
    group = "containers";
    mode = "0400";
    restartUnits = [ "podman-authelia.service" ];
  };

  virtualisation.oci-containers.containers.authelia = {
    imageManifest = ./Dockerfile;
    networks = [ "proxy" ];
    volumes = [
      "${config.sops.templates."authelia-configuration.yml".path}:/config/configuration.yml:ro"
      "${config.sops.secrets."authelia/users_database".path}:/config/users_database.yml:ro"
      "/srv/authelia/data:/data"
    ];
    labels."dockhand.url" = "https://login.lesicnik.eu";
  };

  systemd.services.podman-authelia = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    restartTriggers = [ config.sops.templates."authelia-configuration.yml".file ];
    # Never initialize a fresh identity store instead of the migrated database.
    unitConfig.ConditionPathExists = "/srv/authelia/.migration-complete";
    serviceConfig.Restart = lib.mkForce "always";
  };
}
