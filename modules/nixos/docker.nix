{ lib, ... }:
{
  virtualisation.docker = {
    enable = true;
    storageDriver = "overlay2";
    logDriver = "local";
    # Keep image storage under /var/lib/docker as well as named volumes.
    daemon.settings.features.containerd-snapshotter = false;
    autoPrune.enable = lib.mkForce false;
  };

  # Require the data disk even when Docker is started through its socket.
  # Stop the daemon if the mount goes away.
  systemd.services.docker.unitConfig = {
    RequiresMountsFor = [ "/var/lib/docker" ];
    BindsTo = [ "var-lib-docker.mount" ];
    ConditionPathIsMountPoint = "/var/lib/docker";
  };
}
