{
  config,
  lib,
  pkgs,
  ...
}:
let
  containerUser = config.users.users.containers;
  userManager = "user@${toString containerUser.uid}";
in
{
  virtualisation.docker.enable = false;
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = lib.mkForce false;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = [ pkgs.podman-compose ];
  virtualisation.containers.containersConf.settings.engine.compose_providers = [
    "${pkgs.podman-compose}/bin/podman-compose"
  ];

  users.groups.containers.gid = 1000;
  users.users.containers = {
    isNormalUser = true;
    uid = 1000;
    group = "containers";
    home = "/srv/containers";
    # Create the home only after the data disk is mounted, never during activation.
    createHome = false;
    linger = true;
    autoSubUidGidRange = false;
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];
  };

  # All persistent rootless state, including the default graphroot, lives in this
  # home on the data disk. Never chown existing Docker volumes recursively.
  systemd.services.container-home = {
    description = "Prepare the rootless container user's home on the data disk";
    before = [ "${userManager}.service" ];
    after = [ "srv.mount" ];
    bindsTo = [ "srv.mount" ];
    unitConfig = {
      RequiresMountsFor = [ containerUser.home ];
      ConditionPathIsMountPoint = "/srv";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Docker leaves its filesystem root at 0710 root:root. Allow this group
      # to traverse the mount without exposing or changing old volume contents.
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0710 -o root -g containers /srv";
      ExecStart = "${pkgs.coreutils}/bin/install -d -m 0700 -o containers -g containers ${containerUser.home}";
    };
  };

  # Bind the entire user manager (API, Compose and Quadlets) to the data mount.
  systemd.services.${userManager} = {
    overrideStrategy = "asDropin";
    requires = [ "container-home.service" ];
    after = [
      "container-home.service"
      "srv.mount"
    ];
    bindsTo = [ "srv.mount" ];
    unitConfig.ConditionPathIsMountPoint = "/srv";
  };

  # NixOS enables a rootful API socket by default; expose only the user socket.
  systemd.services.podman.enable = false;
  systemd.sockets.podman.enable = false;
  systemd.user.services.podman.unitConfig.ConditionUser = "containers";
  systemd.user.sockets.podman.unitConfig.ConditionUser = "containers";
  systemd.user.services.podman-restart = {
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "containers";
  };
}
