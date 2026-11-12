{ pkgs, ... }:

{
  # Vhosts retain the backup's web roots and upstreams; restore those separately.
  # Pelican uses the existing NixOS runtime directory and PHP-FPM pool.
  imports = [
    ./adguard.nix
    ./archive.nix
    ./audiobookshelf.nix
    ./auth.nix
    ./authentik.nix
    ./bitmagnet.nix
    ./cah.nix
    ./catbin.nix
    ./cockpit.nix
    ./code.nix
    ./dashy.nix
    ./flaresolverr.nix
    ./forum.nix
    ./freshrss.nix
    ./fullrss.nix
    ./git.nix
    ./gokapi.nix
    ./grimmory.nix
    ./heimdall.nix
    ./homarr.nix
    ./iqbit.nix
    ./jellyfin.nix
    ./jellyseer.nix
    ./jellyvue.nix
    ./kasm.nix
    ./lidarr.nix
    ./localhost.nix
    ./map.nix
    ./matrix.nix
    ./mealie.nix
    ./media.nix
    ./monopoly.nix
    ./nextcloud.nix
    ./onlyhit.nix
    ./onlyhitmc.nix
    ./paste.nix
    ./pelican.nix
    ./php.nix
    ./pipeweaver.nix
    ./plex.nix
    ./portainer.nix
    ./proxmox.nix
    ./qbittorrent.nix
    ./radarr.nix
    ./repo.nix
    ./roam.nix
    ./search.nix
    ./send.nix
    ./sonarr.nix
    ./spacebar.nix
    ./speedtest.nix
    ./spotify.nix
    ./ssh.nix
    ./vaultwarden.nix
    ./webmin.nix
    ./wizarr.nix
    ./zipline.nix
  ];

  services.nginx = {
    # TLS files stay outside the Nix store; nginx needs read access to them.
    additionalModules = [ pkgs.nginxModules.fancyindex ];
    workerProcesses = "auto";
    eventsConfig = ''
      worker_connections 1024;
      multi_accept on;
    '';
    logError = "/var/log/nginx/error.log warn";
    defaultMimeTypes = "${pkgs.nginx}/conf/mime.types";
    typesHashMaxSize = 4096;
    serverNamesHashBucketSize = 128;
    clientMaxBodySize = "1m";
    serverTokens = true;
    recommendedOptimisation = true;
    sslProtocols = "TLSv1.2 TLSv1.3";
    sslCiphers = null;

    commonHttpConfig = ''
      variables_hash_max_size 2048;
      variables_hash_bucket_size 128;

      access_log /var/log/nginx/access.log combined;

      gzip on;
      gzip_comp_level 5;
      gzip_min_length 256;
      gzip_proxied any;
      gzip_vary on;
      gzip_types text/plain text/css text/javascript application/javascript
        application/json application/xml application/xml+rss font/woff2 image/svg+xml;

      ssl_prefer_server_ciphers on;
      ssl_session_cache shared:SSL:50m;
      ssl_session_timeout 1d;

      add_header X-Frame-Options SAMEORIGIN;
      add_header X-Content-Type-Options nosniff;
      add_header X-XSS-Protection "1; mode=block";
      add_header Referrer-Policy no-referrer-when-downgrade;
    '';
  };
}
