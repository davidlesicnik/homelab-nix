{
  config,
  lib,
  pkgs,
  ...
}:
let
  socket = "/run/user/${toString config.users.users.containers.uid}/podman/podman.sock";
  bootstrap = pkgs.writeText "dockhand-bootstrap.mjs" (builtins.readFile ./bootstrap.mjs);
in
{
  virtualisation.oci-containers.containers.dockhand = {
    image = "docker.io/fnsys/dockhand:v1.0.55";
    networks = [ "proxy" ];
    # Container root maps to the unprivileged containers user on the host,
    # giving access to that user's API socket without exposing the rootful API.
    user = "0:0";
    environment = {
      TZ = "Europe/Ljubljana";
      ORIGIN = "https://docker.lesicnik.eu";
      DATA_DIR = "/app/data";
    };
    volumes = [
      "${socket}:/var/run/docker.sock"
      "dockhand-data:/app/data"
      "${bootstrap}:/run/dockhand-bootstrap.mjs:ro"
    ];
    labels."dockhand.url" = "https://docker.lesicnik.eu";
  };

  systemd.services.podman-dockhand = {
    # The common container module orders this after the user manager and /srv.
    # Start its socket before Podman attempts to bind-mount the socket inode.
    preStart = lib.mkBefore ''
      ${pkgs.systemd}/bin/systemctl --user start podman.socket
    '';
    postStart = ''
      # Execute through the user's API service so crun joins the delegated user
      # cgroup; direct exec from this system service cannot enter that cgroup.
      ${config.virtualisation.podman.package}/bin/podman --remote --url unix://${socket} exec dockhand node /run/dockhand-bootstrap.mjs
    '';
    serviceConfig.Restart = lib.mkForce "always";
  };
}
