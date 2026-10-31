{ lib, stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation rec {
  pname = "beszel-agent";
  version = "0.21.1";

  src = fetchurl {
    url = "https://github.com/henrygd/beszel/releases/download/v${version}/beszel-agent_linux_amd64.tar.gz";
    hash = "sha256-O27lkmMuwDuaQzEumaQCA6ez2D/kDdDCWs2h65Fep8A=";
  };
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 beszel-agent $out/bin/beszel-agent
    runHook postInstall
  '';

  meta = {
    description = "Beszel monitoring agent, pinned to the hub version";
    homepage = "https://beszel.dev";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "beszel-agent";
  };
}
