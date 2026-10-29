{ lib, pkgs, ... }:
{
  networking.useDHCP = lib.mkDefault true;
  time.timeZone = lib.mkDefault "Europe/Ljubljana";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  environment.systemPackages = [ pkgs.gitMinimal ];
}
