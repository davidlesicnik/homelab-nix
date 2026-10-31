{ lib, plex, plexRaw, fetchurl }:
let
  # Match the Docker server before importing its database. Once Nixpkgs catches
  # up, resume using its package so regular lock updates also update Plex.
  version = "1.43.5.11029-6bf8af3f0";
in
if lib.versionAtLeast plex.version version then plex else plex.override {
  plexRaw = plexRaw.overrideAttrs {
    inherit version;
    src = fetchurl {
      url = "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_amd64.deb";
      hash = "sha256-Vi7flFa+M4okGC+Df+XVMtfnW6ez1fa+olAwg+d2IuE=";
    };
  };
}
