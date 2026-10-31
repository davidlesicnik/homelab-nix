# Public settings and OIDC clients. Credentials are supplied by SOPS.
{ secret }:
{
  server = {
    address = "tcp://0.0.0.0:9091";
  };
  log = {
    level = "info";
  };
  theme = "auto";
  default_2fa_method = "totp";
  identity_validation = {
    reset_password = {
      jwt_secret = (secret "reset_password_jwt_secret_json");
    };
  };
  authentication_backend = {
    file = {
      path = "/config/users_database.yml";
    };
  };
  access_control = {
    default_policy = "two_factor";
  };
  session = {
    secret = (secret "session_secret_json");
    inactivity = "8760h";
    expiration = "8760h";
    remember_me = "8760h";
    cookies = [
      {
        domain = "lesicnik.eu";
        authelia_url = "https://login.lesicnik.eu";
      }
    ];
  };
  storage = {
    encryption_key = (secret "storage_encryption_key_json");
    local = {
      path = "/data/db.sqlite3";
    };
  };
  notifier = {
    filesystem = {
      filename = "/data/notification.txt";
    };
  };
  totp = {
    disable = false;
    issuer = "lesicnik.eu";
  };
  webauthn = {
    disable = false;
    enable_passkey_login = false;
    display_name = "lesicnik.eu";
    selection_criteria = {
      discoverability = "preferred";
      user_verification = "preferred";
    };
  };
  identity_providers = {
    oidc = {
      hmac_secret = (secret "oidc_hmac_secret_json");
      jwks = [
        {
          key = (secret "oidc_signing_key_0_json");
        }
      ];
      clients = [
        {
          client_id = "bootstrap-client";
          client_name = "Bootstrap Client";
          client_secret = (secret "oidc_client_bootstrap_client_json");
          public = false;
          authorization_policy = "one_factor";
          redirect_uris = [
            "https://app.lesicnik.eu/oauth2/callback"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
        }
        {
          client_id = "lubelogger";
          client_name = "Lubelogger";
          client_secret = (secret "oidc_client_lubelogger_json");
          public = false;
          authorization_policy = "two_factor";
          redirect_uris = [
            "https://fuel.lesicnik.eu/Login/RemoteAuth"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
          ];
          response_types = [
            "code"
          ];
          grant_types = [
            "authorization_code"
          ];
          access_token_signed_response_alg = "none";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_post";
        }
        {
          client_id = "3Ih2rizq46hBInvX58ytzxkkob7cWMQPxbrq5Lkr";
          client_name = "Home Assistant";
          client_secret = (secret "oidc_client_home_assistant_json");
          public = false;
          authorization_policy = "two_factor";
          redirect_uris = [
            "https://ha.lesicnik.eu/auth/openid/callback"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
          response_types = [
            "code"
          ];
          grant_types = [
            "authorization_code"
          ];
          access_token_signed_response_alg = "none";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
        {
          client_id = "proxmox-pve";
          client_name = "Proxmox VE";
          client_secret = (secret "oidc_client_proxmox_ve_json");
          public = false;
          authorization_policy = "two_factor";
          redirect_uris = [
            "https://pve.lesicnik.eu"
            "https://pve.lesicnik.eu/"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
          response_types = [
            "code"
          ];
          grant_types = [
            "authorization_code"
          ];
          require_pkce = true;
          pkce_challenge_method = "S256";
          access_token_signed_response_alg = "none";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
        {
          client_id = "proxmox-pbs";
          client_name = "Proxmox Backup Server";
          client_secret = (secret "oidc_client_proxmox_backup_server_json");
          public = false;
          authorization_policy = "two_factor";
          redirect_uris = [
            "https://pbs.lesicnik.eu"
            "https://pbs.lesicnik.eu/"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
          response_types = [
            "code"
          ];
          grant_types = [
            "authorization_code"
          ];
          require_pkce = true;
          pkce_challenge_method = "S256";
          access_token_signed_response_alg = "none";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
        {
          client_id = "beszel";
          client_name = "Beszel";
          client_secret = (secret "oidc_client_beszel_json");
          public = false;
          authorization_policy = "two_factor";
          redirect_uris = [
            "https://beszel.lesicnik.eu/api/oauth2-redirect"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
          response_types = [
            "code"
          ];
          grant_types = [
            "authorization_code"
          ];
          require_pkce = true;
          pkce_challenge_method = "S256";
          access_token_signed_response_alg = "none";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
        {
          client_id = "tududi";
          client_name = "Tududi";
          client_secret = (secret "oidc_client_tududi_json");
          public = false;
          authorization_policy = "two_factor";
          redirect_uris = [
            "https://task.lesicnik.eu/api/oidc/callback/authelia"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
          response_types = [
            "code"
          ];
          grant_types = [
            "authorization_code"
          ];
          require_pkce = false;
          access_token_signed_response_alg = "none";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
      ];
    };
  };
}
