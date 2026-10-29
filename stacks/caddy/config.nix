{ runCommand, callPackage }:
let
  caddy = callPackage ./package.nix { };
in
runCommand "caddy-config"
  {
    nativeBuildInputs = [ caddy ];
  }
  ''
    mkdir -p "$out"
    cp -r ${./config}/. "$out/"

    # Provision the configuration without starting listeners or issuing certs.
    # Use temporary storage and a dummy token; real credentials stay on the host.
    export HOME="$TMPDIR"
    export XDG_DATA_HOME="$TMPDIR/data"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export CADDY_LOG_DIR="$TMPDIR/logs"
    export CLOUDFLARE_API_TOKEN=0000000000000000000000000000000000000000
    caddy validate --config "$out/Caddyfile" --adapter caddyfile
  ''
