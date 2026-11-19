# Mail MCP

Endpoint: `https://mail-mcp.lesicnik.eu/mcp`. Uses the application's OAuth
passphrase, without Authelia. Initial connection opens a consent page; later
requests use bearer tokens and automatic refresh.

Caddy allows only `/mcp` and the required OAuth routes/methods. Other paths,
including `/attachment/*`, return 404. Binary attachment download links will not
work; inline image/text attachments still work. The container publishes no host
port. The hostname is included in `ddns-updater/config.nix`. Before connecting,
ensure its Cloudflare A record exists and the NAS Caddy forwards this hostname
to the Podman host, following the existing service routes. The public hostname
had no DNS record when this stack was prepared.

## Mailbox.org credentials

The encrypted `accounts_json` starts with `{"accounts":[]}`: no mail is fetched
until you configure an account. Edit with:

```sh
nix develop --command sops stacks/your-mail-mcp/secrets.yaml
```

Replace `accounts_json` with a YAML block containing the JSON from
[`accounts.example.json`](accounts.example.json), using your main email address
and a dedicated **IMAP-only** email app password. Never put real credentials in
the example file. [Mailbox.org settings](https://kb.mailbox.org/en/private/e-mail/e-mail-configuration/)
and [email app passwords](https://kb.mailbox.org/en/private/security-and-privacy/e-mail-password/).

`oauth_passphrase` is already generated and encrypted. To retrieve it for the
initial MCP connection:

```sh
nix develop --command sops --decrypt --extract '["oauth_passphrase"]' stacks/your-mail-mcp/secrets.yaml
```

Merge the credential change through the normal PR/GitOps process. SOPS updates
restart the service. The mailbox is mirrored read-only every 10 minutes;
`status` reports sync health. Everyone authorized sees all configured accounts.

Named volumes `your-mail-mcp-mail` and `your-mail-mcp-index` retain mail, index
and OAuth refresh state. They are included in the host's encrypted Restic backup.
The mirror keeps mail deleted remotely by default.

## Verification

```sh
curl -i https://mail-mcp.lesicnik.eu/                         # 404
curl -i https://mail-mcp.lesicnik.eu/attachment/test/1        # 404
curl -i https://mail-mcp.lesicnik.eu/mcp                      # 401, Bearer challenge
curl -fsS https://mail-mcp.lesicnik.eu/.well-known/oauth-protected-resource/mcp
```

As `containers` on the Podman host: `podman healthcheck run your-mail-mcp`.
Check mailbox sync through the MCP `status` tool after connecting.
