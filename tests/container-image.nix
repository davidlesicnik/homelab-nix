let
  parse = import ../lib/container-image.nix;
  rejects = text: !(builtins.tryEval (parse text)).success;
in
assert parse "FROM ghcr.io/example/app:1.2.3\n" == "ghcr.io/example/app:1.2.3";
assert parse "FROM docker.io/library/postgres:16-alpine@sha256:abc\n" == "docker.io/library/postgres:16-alpine@sha256:abc";
assert rejects "";
assert rejects "FROM app:1\nFROM app:2\n";
assert rejects "FROM app:1 AS build\n";
assert rejects "FROM app:1\nRUN echo unexpected\n";
true
