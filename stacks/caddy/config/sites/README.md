Add `*.caddy` files here. Join upstreams to `proxy`, then commit and push to `main`.

```caddyfile
example.lesicnik.eu {
    import cert
    reverse_proxy example:8080
}
```
