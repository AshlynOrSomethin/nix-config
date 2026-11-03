{ config, pkgs, ... }:

{
  services.qbittorrent = {
    enable = true;
    user = "ashlyn";
    group = "users";
    webuiPort = 8085;
  };

  systemd.services.media-access = {
    description = "Grant ashlyn recursive access to media";
    wantedBy = [ "multi-user.target" ];
    before = [ "qbittorrent.service" ];
    unitConfig.RequiresMountsFor = [ "/media/sda" "/media/md" ];
    path = [ pkgs.acl pkgs.findutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      setfacl -R -P -m u:ashlyn:rwx /media
      find -P /media -type d -exec setfacl -m d:u:ashlyn:rwx {} +
    '';
  };

  systemd.services.qbittorrent = {
    requires = [ "media-access.service" ];
    after = [ "media-access.service" ];
    restartTriggers = [
      config.home-manager.users.ashlyn.xdg.configFile."qBittorrent/qBittorrent.conf".source
    ];
    preStart = ''
      ${pkgs.coreutils}/bin/install -Dm600 \
        ${config.home-manager.users.ashlyn.xdg.configFile."qBittorrent/qBittorrent.conf".source} \
        /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf
    '';
  };
}
