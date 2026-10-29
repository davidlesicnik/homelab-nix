{ caddy }:
caddy.withPlugins {
  plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
  hash = "sha256-tubXIDCJnO2mvdnPlZclwDhNGaeeYLSt7lnni3+pXDo=";
}
