{ config, ... }:
{
  # Each host pulls its own configuration from main, using the committed lockfile.
  system.autoUpgrade = {
    enable = true;
    flake = "git+https://github.com/davidlesicnik/homelab-nix.git?ref=main#${config.networking.hostName}";
    upgrade = false;
    flags = [ "--no-update-lock-file" ];
    dates = "*:0/15";
    randomizedDelaySec = "60s";
    operation = "switch";
    allowReboot = false;
  };
}
