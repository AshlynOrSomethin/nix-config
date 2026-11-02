{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."nextcloud.pulsar.ltd-http" = {
    serverName = "nextcloud.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = nextcloud.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://$server_name$request_uri;
    '';
  };
  services.nginx.virtualHosts."nextcloud.pulsar.ltd" = {
    http2 = true;
    serverName = "nextcloud.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    root = "/usr/share/webapps/nextcloud";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."= /" = {
      priority = 100;
      extraConfig = ''
        if ( $http_user_agent ~ ^DavClnt ) {
          return 302 /remote.php/webdav/$is_args$args;
        }
      '';
    };
    locations."= /robots.txt" = {
      priority = 101;
      extraConfig = ''
        allow all;
        log_not_found off;
        access_log off;
      '';
    };
    locations."^~ /.well-known" = {
      priority = 102;
      extraConfig = ''
        location = /.well-known/carddav {
          return 301 /remote.php/dav/;
        }
        location = /.well-known/caldav {
          return 301 /remote.php/dav/;
        }
        location /.well-known/acme-challenge {
          try_files $uri $uri/ =404;
        }
        location /.well-known/pki-validation {
          try_files $uri $uri/ =404;
        }
        return 301 /index.php$request_uri;
      '';
    };
    locations."~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)" = {
      priority = 103;
      extraConfig = ''
        return 404;
      '';
    };
    locations."~ ^/(?:\\.|autotest|occ|issue|indie|db_|console)" = {
      priority = 104;
      extraConfig = ''
        return 404;
      '';
    };
    locations."~ \\.php(?:$|/)" = {
      priority = 105;
      tryFiles = "$fastcgi_script_name =404";
      extraConfig = ''
        fastcgi_pass unix:/run/php-fpm-legacy/nextcloud.sock;
        rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+|.+\/richdocumentscode\/proxy) /index.php$request_uri;
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        set $path_info $fastcgi_path_info;
        include ${pkgs.nginx}/conf/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        fastcgi_max_temp_file_size 0;
      '';
    };
    locations."~ \\.(?:css|js|svg|gif|map)$" = {
      priority = 106;
      tryFiles = "$uri /index.php$request_uri";
      extraConfig = ''
        expires 6M;
        access_log off;
      '';
    };
    locations."~ \\.woff2?$" = {
      priority = 107;
      tryFiles = "$uri /index.php$request_uri";
      extraConfig = ''
        expires 7d;
        access_log off;
      '';
    };
    locations."/remote" = {
      priority = 108;
      extraConfig = ''
        return 301 /remote.php$request_uri;
      '';
    };
    locations."/" = {
      priority = 109;
      tryFiles = "$uri $uri/ /index.php$request_uri";
    };
    extraConfig = ''
      client_max_body_size 512M;
      fastcgi_buffers 64 4K;
      include ${config.services.nginx.defaultMimeTypes};
      types {
        application/javascript mjs;
      }
      gzip on;
      gzip_vary on;
      gzip_comp_level 4;
      gzip_min_length 256;
      gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
      gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
      add_header Referrer-Policy "no-referrer" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-Download-Options "noopen" always;
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Permitted-Cross-Domain-Policies "none" always;
      add_header X-Robots-Tag "none" always;
      add_header X-XSS-Protection "1; mode=block" always;
      fastcgi_hide_header X-Powered-By;
      index index.php index.html /index.php$request_uri;
    '';
  };
}
