{ lib, pkgs, ... }:
{
  nix.settings.trusted-public-keys = [
    (lib.removeSuffix "\n" (builtins.readFile ./cache-public-key))
  ];

  systemd.services.plex-update = {
    description = "Install the Plex system built by GitHub Actions";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.gitMinimal pkgs.nix pkgs.systemd ];
    # A switch can change this unit while it is still completing the update.
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "plex-update";
      UMask = "0077";
      TimeoutStartSec = "30min";
      ExecStart = "${pkgs.python3}/bin/python3 ${../../scripts/update-plex-lxc.py}";
    };
  };
  systemd.timers.plex-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "2min";
      RandomizedDelaySec = "15s";
    };
  };
}
