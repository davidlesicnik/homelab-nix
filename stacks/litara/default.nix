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
    "podman-network-litara.service"
    "sops-install-secrets.service"
  ];
in
{
  sops.secrets = lib.genAttrs [ "litara/database_url" "litara/jwt_secret" "litara/postgres_password" ] (name: {
    sopsFile = ./secrets.yaml;
    key = lib.removePrefix "litara/" name;
  });
  sops.templates = {
    "litara.env" = {
      content = ''
        DATABASE_URL=${config.sops.placeholder."litara/database_url"}
        JWT_SECRET=${config.sops.placeholder."litara/jwt_secret"}
      '';
      owner = "containers";
      group = "containers";
      mode = "0400";
      restartUnits = [ "podman-litara.service" ];
    };
    "litara-postgres.env" = {
      content = ''
        POSTGRES_PASSWORD=${config.sops.placeholder."litara/postgres_password"}
      '';
      owner = "containers";
      group = "containers";
      mode = "0400";
      restartUnits = [ "podman-litara-postgres.service" ];
    };
  };

  virtualisation.oci-containers.containers = {
    litara = {
      # Preserve the exact running NAS image for this data migration.
      image = "ghcr.io/litara-app/litara@sha256:d42ab3bf0c6cefaa05990f1dab9d0093a5bff41e5e1c2b9d1e3e15a9fa9a05a5";
      dependsOn = [ "litara-postgres" ];
      networks = [ "proxy" "litara" ];
      environmentFiles = [ config.sops.templates."litara.env".path ];
      volumes = [ "/srv/litara/books:/books" ];
      labels."dockhand.url" = "https://books.lesicnik.eu";
    };
    litara-postgres = {
      image = "docker.io/library/postgres:16-alpine@sha256:f4610795587492cd4fb887c2dc3de301b813278bb6f616992061141b5f15ac36";
      networks = [ "litara" ];
      environment = {
        POSTGRES_USER = "postgres";
        POSTGRES_DB = "litara";
      };
      environmentFiles = [ config.sops.templates."litara-postgres.env".path ];
      volumes = [ "litara-postgres-data:/var/lib/postgresql/data" ];
      # Preserve the database hostname in the source application's DATABASE_URL.
      extraOptions = [
        "--network-alias=postgres"
        "--health-cmd=pg_isready -U postgres -d litara"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=12"
      ];
    };
  };

  systemd.services = {
    podman-network-litara = {
      description = "Ensure the private rootless Litara database network exists";
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
        podman network exists litara || podman network create --internal --driver bridge litara
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "containers";
        Group = "containers";
      };
    };
    podman-litara = {
      requires = dependencies;
      after = dependencies;
      # Do not let the application initialize or scan an empty migration target.
      unitConfig.ConditionPathExists = "/srv/litara/.migration-complete";
      serviceConfig.Restart = lib.mkForce "always";
    };
    podman-litara-postgres = {
      requires = dependencies;
      after = dependencies;
      preStart = lib.mkBefore ''
        ${pkgs.systemd}/bin/systemctl --user start podman.socket
      '';
      # Finish database startup before a dependent application can connect.
      postStart = ''
        for attempt in $(seq 1 60); do
          if ${podmanApi} exec litara-postgres pg_isready -U postgres -d litara; then
            exit 0
          fi
          sleep 1
        done
        echo "Litara PostgreSQL did not become ready within 60 attempts" >&2
        exit 1
      '';
      serviceConfig.Restart = lib.mkForce "always";
    };
  };
}
