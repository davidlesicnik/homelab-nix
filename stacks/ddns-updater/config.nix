{ cloudflareApiToken }:
let
  # Add, remove, or edit records here. GitOps recreates the container when the
  # generated configuration changes; the API token stays in encrypted secrets.
  records = [
    {
      domain = "dns.lesicnik.eu";
      proxied = false;
    }
    {
      domain = "fuel.lesicnik.eu";
      proxied = true;
    }
    {
      domain = "ha.lesicnik.eu";
      proxied = true;
    }
    {
      domain = "login.lesicnik.eu";
      proxied = true;
    }
    {
      domain = "vpn.lesicnik.eu";
      proxied = false;
    }
    {
      domain = "phone.lesicnik.eu";
      proxied = true;
    }
  ];
in
{
  settings = map (record: {
    provider = "cloudflare";
    zone_identifier = "07492488333c2516382af2a54f294d56";
    ttl = 1;
    token = cloudflareApiToken;
    ip_version = "ipv4";
  } // record) records;
}
