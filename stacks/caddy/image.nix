{
  dockerTools,
  cacert,
  tzdata,
  callPackage,
}:
let
  caddy = callPackage ./package.nix { };
in
dockerTools.buildLayeredImage {
  name = "localhost/caddy";
  tag = builtins.substring 0 16 (builtins.hashString "sha256" (toString caddy));
  contents = [
    caddy
    cacert
    tzdata
  ];
  config = {
    Entrypoint = [ "${caddy}/bin/caddy" ];
    Cmd = [
      "run"
      "--config"
      "/etc/caddy/Caddyfile"
      "--adapter"
      "caddyfile"
    ];
    Env = [
      "XDG_CONFIG_HOME=/config"
      "XDG_DATA_HOME=/data"
    ];
    ExposedPorts = {
      "80/tcp" = { };
      "443/tcp" = { };
      "443/udp" = { };
    };
  };
}
