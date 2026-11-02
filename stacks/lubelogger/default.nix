{
  config,
  lib,
  pkgs,
  ...
}:
let
  containerUser = config.users.users.containers;
  userManager = "user@${toString containerUser.uid}.service";
  runtimeDirectory = "/run/user/${toString containerUser.uid}";
  podman = config.virtualisation.podman.package;
  podmanApi = "${podman}/bin/podman --remote --url unix://${runtimeDirectory}/podman/podman.sock";
  dependencies = [
    "podman-network-lubelogger.service"
    "sops-install-secrets.service"
  ];
in
{
  sops.secrets = lib.genAttrs [ "lubelogger/app_env" "lubelogger/postgres_env" ] (name: {
    sopsFile = ./secrets.yaml;
    key = lib.removePrefix "lubelogger/" name;
    owner = "containers";
    group = "containers";
    mode = "0400";
    restartUnits = [ (if name == "lubelogger/app_env" then "podman-lubelogger.service" else "podman-lubelogger-db.service") ];
  });

  virtualisation.oci-containers.containers = {
    lubelogger = {
      imageManifest = ./Dockerfile;
      dependsOn = [ "lubelogger-db" ];
      networks = [ "proxy" "lubelogger" ];
      environment = {
        "LANG" = "sl_SI";
        "LC_ALL" = "sl_SI";
        "LUBELOGGER_ALLOWED_FILE_EXTENSIONS" = "*";
        "OpenIDConfig__AuthURL" = "https://login.lesicnik.eu/api/oidc/authorization";
        "OpenIDConfig__ClientId" = "lubelogger";
        "OpenIDConfig__DisableRegularLogin" = "false";
        "OpenIDConfig__LogOutURL" = "https://login.lesicnik.eu/logout";
        "OpenIDConfig__Name" = "Authelia";
        "OpenIDConfig__RedirectURL" = "https://fuel.lesicnik.eu/Login/RemoteAuth";
        "OpenIDConfig__Scope" = "openid profile email";
        "OpenIDConfig__TokenURL" = "https://login.lesicnik.eu/api/oidc/token";
        "OpenIDConfig__UsePKCE" = "false";
        "OpenIDConfig__UserInfoURL" = "https://login.lesicnik.eu/api/oidc/userinfo";
        "OpenIDConfig__ValidateState" = "false";
      };
      environmentFiles = [ config.sops.secrets."lubelogger/app_env".path ];
      volumes = [
        "/srv/lubelogger/data:/App/data"
        "/srv/lubelogger/keys:/root/.aspnet/DataProtection-Keys"
      ];
      labels."dockhand.url" = "https://fuel.lesicnik.eu";
    };
    lubelogger-db = {
      imageManifest = ./postgres.Dockerfile;
      networks = [ "lubelogger" ];
      environmentFiles = [ config.sops.secrets."lubelogger/postgres_env".path ];
      # PostgreSQL 18 stores PGDATA below this version-independent mount.
      volumes = [ "lubelogger-postgres-data:/var/lib/postgresql" ];
      extraOptions = [
        "--health-cmd=pg_isready -U lubelogger -d lubelogger"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=12"
      ];
    };
  };

  systemd.services = {
    podman-network-lubelogger = {
      description = "Ensure the private rootless LubeLogger database network exists";
      requires = [ userManager ];
      after = [ userManager "srv.mount" ];
      bindsTo = [ userManager "srv.mount" ];
      unitConfig.ConditionPathIsMountPoint = "/srv";
      environment = {
        HOME = containerUser.home;
        XDG_RUNTIME_DIR = runtimeDirectory;
      };
      path = [ podman ];
      script = ''
        podman network exists lubelogger || podman network create --internal --driver bridge lubelogger
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "containers";
        Group = "containers";
      };
    };
    podman-lubelogger = {
      requires = dependencies;
      after = dependencies;
      # Do not let the application initialize or scan an empty migration target.
      unitConfig.ConditionPathExists = "/srv/lubelogger/.migration-complete";
      serviceConfig.Restart = lib.mkForce "always";
    };
    podman-lubelogger-db = {
      requires = dependencies;
      after = dependencies;
      preStart = lib.mkBefore ''
        ${pkgs.systemd}/bin/systemctl --user start podman.socket
      '';
      # Finish database startup before a dependent application can connect.
      postStart = ''
        for attempt in $(seq 1 60); do
          if ${podmanApi} exec lubelogger-db pg_isready -U lubelogger -d lubelogger; then
            exit 0
          fi
          sleep 1
        done
        echo "LubeLogger PostgreSQL did not become ready within 60 attempts" >&2
        exit 1
      '';
      serviceConfig.Restart = lib.mkForce "always";
    };
  };
}
