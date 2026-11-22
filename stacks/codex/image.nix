{
  dockerTools,
  buildEnv,
  writeTextDir,
  bashInteractive,
  bubblewrap,
  cacert,
  fetchurl,
  runCommand,
  coreutils,
  curl,
  diffutils,
  findutils,
  gawk,
  gh,
  git,
  gnugrep,
  gnused,
  openssh,
  python3,
  ripgrep,
}:
let
  # This release handles nested /proc mounts with current Bubblewrap.
  version = "0.171.0";
  archive = fetchurl {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}-linux-x64.tgz";
    hash = "sha512-l66NZkQgdk2C3pbcfULDz42yEUB581MVA6I+Y43Wp4OIqEy73HCdmZ0GTjeAHY2ycuH4N00d9VsLrwT1jxshTw==";
  };
  codex = runCommand "codex-${version}" { } ''
    mkdir -p "$out"
    tar -xzf ${archive} -C "$out" --strip-components=3 package/vendor/x86_64-unknown-linux-musl
  '';
  tools = buildEnv {
    name = "codex-workspace-tools";
    paths = [
      bashInteractive
      bubblewrap
      codex
      coreutils
      curl
      diffutils
      findutils
      gawk
      gh
      git
      gnugrep
      gnused
      openssh
      python3
      ripgrep
    ];
    pathsToLink = [ "/bin" ];
  };
in
dockerTools.buildLayeredImage {
  name = "localhost/codex";
  maxLayers = 12;
  contents = [
    tools
    dockerTools.usrBinEnv
    dockerTools.caCertificates
    (writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      codex:x:1000:1000:Codex:/home/codex:/bin/bash
    '')
    (writeTextDir "etc/group" ''
      root:x:0:
      codex:x:1000:
    '')
  ];
  extraCommands = ''
    mkdir -p home/codex workspace tmp
    chmod 1777 tmp
  '';
  fakeRootCommands = ''
    chown 1000:1000 home/codex workspace
    chmod 0700 home/codex
  '';
  config = {
    User = "1000:1000";
    WorkingDir = "/workspace";
    Env = [
      "HOME=/home/codex"
      "PATH=/bin"
      "SHELL=/bin/bash"
      "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
      "GIT_SSL_CAINFO=${cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
    # Use the daemon's normal control socket so the CLI can pair with this process.
    Cmd = [ "codex" "app-server" "--remote-control" "--listen" "unix://" ];
  };
}
