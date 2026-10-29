Add extra sites as `*.caddy` files in this directory. The main Caddyfile imports
all of them automatically. For example, `example.caddy` could contain:

```caddyfile
example.lesicnik.eu {
    import cert
    reverse_proxy example:8080
}
```

The upstream container must join the rootless `proxy` network. Commit new files
along with your changes and push to `main`; GitOps validates the configuration
and restarts Caddy when applying the new NixOS generation.
