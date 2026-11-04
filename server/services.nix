{ pkgs, inputs, ... }:

{
  imports = [ ./nginx/nginx.nix ];

  services.nginx.enable = true;

  services.jellyfin = {
    enable = true;
    package = pkgs.jellyfin.overrideAttrs (old: {
      makeWrapperArgs = map (arg:
        if arg == "--webdir=${pkgs.jellyfin-web}/share/jellyfin-web"
        then "--webdir=/var/lib/jellyfin/web"
        else arg
      ) old.makeWrapperArgs;
    });
    openFirewall = true;
    dataDir = "/var/lib/jellyfin/data";
    configDir = "/var/lib/jellyfin";
    cacheDir = "/var/lib/jellyfin/cache";
    logDir = "/var/lib/jellyfin/log";
  };
  environment.systemPackages = [ pkgs.jellyfin-ffmpeg ];
  users.users.jellyfin = {
    # Keep access to media-side trickplay files created by the old container.
    uid = 980;
    extraGroups = [ "render" "video" ];
  };
  systemd.tmpfiles.rules = [
    "Z /var/lib/jellyfin - jellyfin jellyfin -"
  ];
  systemd.services.jellyfin = {
    conflicts = [ "docker-jellyfin.service" ];
    after = [ "docker-jellyfin.service" ];
    unitConfig.RequiresMountsFor = [ "/media/sda" "/media/md" ];
    preStart = ''
      ${pkgs.rsync}/bin/rsync -rlt --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
        ${pkgs.jellyfin-web}/share/jellyfin-web/ /var/lib/jellyfin/web/
    '';
    # Preserve absolute paths stored by the container without creating /config on the host.
    serviceConfig.BindPaths = [ "/var/lib/jellyfin:/config" ];
    serviceConfig.BindReadOnlyPaths = [
      "${pkgs.jellyfin-ffmpeg}/bin:/usr/lib/jellyfin-ffmpeg"
    ];
  };

  services.udisks2.enable = true;
  services.fprintd.enable = true;
  services.printing.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "ashlyn" ];
      MaxAuthTries = 5;
      PerSourcePenalties = "crash:3600s authfail:3600s max:86400s";
    };
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.redis = {
    package = pkgs.valkey;
    servers."pelican" = {
      enable = true;
      port = 6379;
      bind = "127.0.0.1";
      requirePassFile = "/var/lib/secrets/pelican-redis-password";
      settings = {
        maxmemory = "256mb";
        maxmemory-policy = "allkeys-lru";
        appendonly = "yes";
      };
    };
  };

  services.vscode-server.enable = true;

}
