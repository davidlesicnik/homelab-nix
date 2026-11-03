{ config, lib, ... }:
let
  containerUser = config.users.users.containers;
  userManager = "user@${toString containerUser.uid}.service";
  runtimeDirectory = "/run/user/${toString containerUser.uid}";
in
{
  imports = [ ./podman.nix ];

  # Extend the native NixOS container options with this host's rootless default.
  options.virtualisation.oci-containers.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }: {
          options.imageManifest = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Dockerfile containing one FROM image reference, monitored by Dependabot.";
          };
          options.healthcheck = lib.mkOption {
            description = "Container-local health probe, executed directly without an implicit shell.";
            type = lib.types.submodule {
              options = {
                command = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                interval = lib.mkOption {
                  type = lib.types.str;
                  default = "30s";
                };
                timeout = lib.mkOption {
                  type = lib.types.str;
                  default = "10s";
                };
                retries = lib.mkOption {
                  type = lib.types.ints.positive;
                  default = 3;
                };
                startPeriod = lib.mkOption {
                  type = lib.types.str;
                  default = "60s";
                };
              };
            };
            default = { };
          };
          config.extraOptions = lib.mkIf (config.healthcheck.command != [ ]) [
            "--health-cmd=${builtins.toJSON config.healthcheck.command}"
            "--health-interval=${config.healthcheck.interval}"
            "--health-timeout=${config.healthcheck.timeout}"
            "--health-retries=${toString config.healthcheck.retries}"
            "--health-start-period=${config.healthcheck.startPeriod}"
            "--health-on-failure=none"
          ];
          config.image = lib.mkIf (config.imageManifest != null) (
            import ../../lib/container-image.nix (builtins.readFile config.imageManifest)
          );
          config.podman.user = lib.mkDefault "containers";
          config.labels = {
            "dockhand.update" = lib.mkDefault "false";
            "dockhand.adopt" = lib.mkDefault "false";
            "dockhand.tags" = lib.mkDefault "NixOS";
          };
        }
      )
    );
  };

  config = {
    virtualisation.oci-containers.backend = "podman";

    assertions =
      lib.mapAttrsToList (name: container: {
        assertion = container.podman.user == "containers";
        message = "Container ${name} must run as the rootless containers user.";
      }) config.virtualisation.oci-containers.containers
      ++ lib.mapAttrsToList (name: container: {
        assertion = container.healthcheck.command != [ ];
        message = "Container ${name} needs an explicit healthcheck.command.";
      }) config.virtualisation.oci-containers.containers
      ++ lib.mapAttrsToList (name: container: {
        assertion =
          container.imageFile != null
          || (
            container.imageManifest != null
            && lib.hasInfix "/stacks/" (toString container.imageManifest)
            && lib.hasInfix "Dockerfile" (builtins.baseNameOf container.imageManifest)
          );
        message = "Container ${name} needs imageManifest pointing to a Dockerfile under stacks/ for Dependabot, or a locally built imageFile.";
      }) config.virtualisation.oci-containers.containers;

    # Frontends opt into this shared network with networks = [ "proxy" ].
    systemd.services = {
      podman-network-proxy = {
        description = "Ensure the shared rootless proxy network exists";
        requires = [ userManager ];
        after = [
          userManager
          "srv.mount"
        ];
        bindsTo = [
          userManager
          "srv.mount"
        ];
        unitConfig.ConditionPathIsMountPoint = "/srv";
        environment = {
          HOME = containerUser.home;
          XDG_RUNTIME_DIR = runtimeDirectory;
        };
        path = [ config.virtualisation.podman.package ];
        script = ''
          # Reach host-networked AdGuard through pasta's host alias. The LAN
          # address refers to pasta's own interface, and its default DNS
          # forwarder retains the resolver that was present at startup.
          if podman network exists proxy; then
            podman network update --dns-add 169.254.1.2 proxy
          else
            podman network create --driver bridge --dns 169.254.1.2 proxy
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "containers";
          Group = "containers";
        };
      };
    }
    // lib.mapAttrs' (
      _: container:
      let
        proxyDependency = lib.optional (builtins.elem "proxy" container.networks) "podman-network-proxy.service";
      in
      lib.nameValuePair container.serviceName {
        # Native OCI containers are system services running as an unprivileged
        # user. Give them the same mount protection as the user's own services.
        requires = [ userManager ] ++ proxyDependency;
        after = [
          userManager
          "srv.mount"
        ]
        ++ proxyDependency;
        bindsTo = [
          userManager
          "srv.mount"
        ];
        unitConfig.ConditionPathIsMountPoint = "/srv";
        environment.XDG_RUNTIME_DIR = runtimeDirectory;
      }
    ) config.virtualisation.oci-containers.containers;
  };
}
