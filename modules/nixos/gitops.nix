{ config, lib, pkgs, ... }:
{
  # Each host pulls its own configuration from main, using the committed lockfile.
  system.autoUpgrade = {
    enable = true;
    flake = "git+https://github.com/davidlesicnik/homelab-nix.git?ref=main#${config.networking.hostName}";
    upgrade = false;
    flags = [ "--no-update-lock-file" ];
    dates = "minutely";
    randomizedDelaySec = "0";
    operation = "switch";
    allowReboot = false;
  };

  systemd.timers.nixos-upgrade.timerConfig.AccuracySec = "1s";

  # Check Git cheaply each minute; rebuild only when main has changed.
  systemd.services.nixos-upgrade.serviceConfig.ExecCondition = pkgs.writeShellScript "check-homelab-revision" ''
    remote_revision="$(${lib.getExe pkgs.gitMinimal} ls-remote --exit-code https://github.com/davidlesicnik/homelab-nix.git refs/heads/main)" || exit 255
    remote_revision="''${remote_revision%%[[:space:]]*}"
    [[ "$remote_revision" =~ ^[0-9a-f]{40}$ ]] || exit 255
    [[ "$remote_revision" != ${lib.escapeShellArg (if config.system.configurationRevision == null then "" else config.system.configurationRevision)} ]]
  '';
}
