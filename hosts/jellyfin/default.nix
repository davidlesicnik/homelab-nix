{ lib, pkgs }:

let
  initialEncoding = pkgs.writeText "jellyfin-encoding.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <EncodingOptions>
      <HardwareAccelerationType>vaapi</HardwareAccelerationType>
      <VaapiDevice>/dev/dri/renderD128</VaapiDevice>
      <EnableHardwareEncoding>true</EnableHardwareEncoding>
      <HardwareDecodingCodecs>
        <string>h264</string>
        <string>hevc</string>
        <string>hevc10bit</string>
      </HardwareDecodingCodecs>
    </EncodingOptions>
  '';

  initializeEncoding = pkgs.writeShellScript "jellyfin-initialize-encoding" ''
    if [ ! -e /var/lib/jellyfin/config/encoding.xml ]; then
      ${pkgs.coreutils}/bin/install -D -m 0600 ${initialEncoding} \
        /var/lib/jellyfin/config/encoding.xml
    fi
  '';

  users = pkgs.writeText "jellyfin.conf" ''
    g render -
    g jellyfin 1000
    u jellyfin 1000:1000 "Jellyfin Media Server" /var/lib/jellyfin /usr/sbin/nologin
    m jellyfin render
  '';

  service = pkgs.writeText "jellyfin.service" ''
    [Unit]
    Description=Jellyfin Media Server
    Wants=network-online.target
    After=network-online.target
    ConditionPathIsMountPoint=/mnt/media

    [Service]
    User=jellyfin
    Group=jellyfin
    StateDirectory=jellyfin
    CacheDirectory=jellyfin
    WorkingDirectory=/var/lib/jellyfin
    Environment=LIBVA_DRIVER_NAME=iHD
    Environment=LIBVA_DRIVERS_PATH=${pkgs.intel-media-driver}/lib/dri
    ExecStartPre=${initializeEncoding}
    ExecStart=${lib.getExe pkgs.jellyfin} --datadir /var/lib/jellyfin --configdir /var/lib/jellyfin/config --cachedir /var/cache/jellyfin --logdir /var/lib/jellyfin/log
    NoNewPrivileges=yes
    UMask=0077
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target
  '';
in
pkgs.runCommand "jellyfin-debian" { passthru.jellyfinVersion = pkgs.jellyfin.version; } ''
  install -Dm0444 ${users} "$out/lib/sysusers.d/jellyfin.conf"
  install -Dm0444 ${service} "$out/lib/systemd/system/jellyfin.service"
''
