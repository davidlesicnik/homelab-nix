# A single FROM declaration is shared by NixOS and Dependabot.
contents:
let
  match = builtins.match "FROM ([^[:space:]]+)[[:space:]]*" contents;
in
if match == null then
  throw "Container image Dockerfile must contain exactly one FROM <image> declaration"
else
  builtins.head match
