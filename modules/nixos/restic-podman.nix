{
  config,
  lib,
  pkgs,
  ...
}:
let
  containers = config.virtualisation.oci-containers.containers;
  userManager = "user@${toString config.users.users.containers.uid}.service";
  volumeRoot = "${config.users.users.containers.home}/.local/share/containers/storage/volumes";
  sourcesFor =
    container:
    lib.filter (source: source != null) (
      map (
        mount:
        let
          source = builtins.head (lib.splitString ":" mount);
        in
        if lib.hasPrefix "/srv/" source then
          source
        else if !lib.hasPrefix "/" source then
          "${volumeRoot}/${source}/_data"
        else
          null
      ) container.volumes
    );
  stateful = lib.filterAttrs (_: container: sourcesFor container != [ ]) containers;
  sources = lib.sort builtins.lessThan (
    lib.unique (lib.concatMap sourcesFor (builtins.attrValues stateful))
  );
  stage = "/srv/.restic-podman";
  state = "/var/lib/restic-podman";
  manifest = pkgs.writeText "podman-backup-manifest.json" (
    builtins.toJSON {
      inherit sources stage state;
      copyTimeoutSeconds = config.homelab.podmanBackup.copyTimeoutSeconds;
      services = map (container: "${container.serviceName}.service") (builtins.attrValues stateful);
      migrationMarkers = lib.unique (
        map (source: "/srv/${builtins.elemAt (lib.splitString "/" source) 2}/.migration-complete") (
          lib.filter (source: !lib.hasPrefix volumeRoot source) sources
        )
      );
      revision = config.system.configurationRevision;
      images = lib.mapAttrs (_: container: container.image) containers;
      mounts = lib.mapAttrs (_: container: container.volumes) containers;
    }
  );
  staging = "${pkgs.python3}/bin/python3 ${../../scripts/restic-podman-stage.py} ${manifest}";
  knownHosts = pkgs.writeText "restic-nas-known-hosts" ''
    192.168.10.9 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOYbhA1UenqMzA/xZasr6+FyqWAIYEibf7TRjrbzeL7+
  '';
  sshCommand = lib.concatStringsSep " " [
    "${pkgs.openssh}/bin/ssh -F /dev/null"
    "-i ${config.sops.secrets."restic/ssh-key".path}"
    "-oIdentitiesOnly=yes -oBatchMode=yes -oStrictHostKeyChecking=yes"
    "-oUserKnownHostsFile=${knownHosts} -oConnectTimeout=15"
    "-oServerAliveInterval=30 -oServerAliveCountMax=3"
    "restic@192.168.10.9 -s sftp"
  ];
  restic = lib.escapeShellArgs [
    "${pkgs.restic}/bin/restic"
    "--repo=sftp:restic@192.168.10.9:/docker_restic"
    "--password-file=${config.sops.secrets."restic/password".path}"
    "--option=sftp.command=${sshCommand}"
  ];
in
{
  options.homelab.podmanBackup.copyTimeoutSeconds = lib.mkOption {
    type = lib.types.ints.positive;
    default = 3600;
    description = "Maximum seconds for copying each Podman data source while applications are stopped.";
  };

  config = {
    sops.secrets = {
      "restic/ssh-key" = {
        sopsFile = ../../hosts/podman/secrets.yaml;
        key = "restic_ssh_key";
        mode = "0400";
      };
      "restic/password" = {
        sopsFile = ../../hosts/podman/secrets.yaml;
        key = "restic_password";
        mode = "0400";
      };
    };

    services.restic.backups.podman = {
      repository = "sftp:restic@192.168.10.9:/docker_restic";
      passwordFile = config.sops.secrets."restic/password".path;
      extraOptions = [ "sftp.command='${sshCommand}'" ];
      paths = [ stage ];
      extraBackupArgs = [
        "--host=podman"
        "--tag=podman"
        "--one-file-system"
      ];
      timerConfig = {
        OnCalendar = "*-*-* 01:00:00 Europe/Ljubljana";
        Persistent = true;
        RandomizedDelaySec = "0";
        AccuracySec = "1s";
      };
      # Run only after a successful backup. Never expire snapshots after a failed copy.
      pruneOpts = [
        "--host=podman"
        "--tag=podman"
        "--group-by=host,tags"
        "--keep-daily=14"
        "--keep-weekly=8"
        "--keep-monthly=12"
        "--keep-yearly=3"
      ];
      # Validate metadata and a random sample of stored data on every run.
      # systemd requires a doubled percent sign in ExecStart.
      checkOpts = [ "--read-data-subset=5%%" ];
      backupPrepareCommand = ''
        # Fail on NAS/credentials errors before taking any applications offline.
        ${restic} cat config >/dev/null || ${restic} init || exit "$?"
        ${staging} prepare
      '';
      # ExecStopPost also runs when preparation, backup, or integrity checks fail.
      backupCleanupCommand = "${staging} recover";
    };

    systemd.services.restic-backups-podman = {
      requires = [
        "sops-install-secrets.service"
        userManager
      ];
      after = [
        "sops-install-secrets.service"
        userManager
        "srv.mount"
      ];
      unitConfig = {
        RequiresMountsFor = [ "/srv" ];
        ConditionPathIsMountPoint = "/srv";
      };
      path = [
        pkgs.rsync
        pkgs.systemd
        pkgs.coreutils
        pkgs.diffutils
      ];
      # Verify a real restore of the recovery manifest before reporting success.
      postStart = ''
        ${restic} dump --host podman --tag podman latest ${stage}/manifest.json > "$RUNTIME_DIRECTORY/restored-manifest.json"
        cmp ${stage}/manifest.json "$RUNTIME_DIRECTORY/restored-manifest.json"
        date --iso-8601=seconds > ${state}/last-success
      '';
      serviceConfig = {
        StateDirectory = "restic-podman";
        StateDirectoryMode = "0700";
        UMask = "0077";
        Nice = 10;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
        TimeoutStartSec = "6h";
        TimeoutStopSec = "10min";
      };
    };
  };
}
