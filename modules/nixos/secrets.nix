{
  sops.useSystemdActivation = true;
  # Provision this private identity once, or restore it when reinstalling.
  # Public recipients and encrypted stack secrets are managed in Git.
  sops.age = {
    keyFile = "/var/lib/sops-nix/key.txt";
    sshKeyPaths = [ ];
  };
  sops.gnupg.sshKeyPaths = [ ];
}
