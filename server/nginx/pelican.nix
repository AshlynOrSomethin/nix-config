{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."panel.pulsar.ltd-http" = {
    serverName = "panel.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = panel.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://$server_name$request_uri;
    '';
  };
  services.nginx.virtualHosts."panel.pulsar.ltd" = {
    serverName = "panel.pulsar.ltd";
    root = config.services.pelican-panel.runtimeLocation + "/public";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      tryFiles = "$uri $uri/ /index.php?$query_string";
    };
    locations."~ \\.php$" = {
      priority = 101;
      extraConfig = ''
        include ${pkgs.nginx}/conf/fastcgi_params;
        fastcgi_pass unix:${config.services.phpfpm.pools.${config.services.pelican-panel.phpfpm.poolName}.socket};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M\n post_max_size = 100M";
        fastcgi_param HTTP_PROXY "";
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_intercept_errors off;
      '';
    };
    locations."~ /\\.(?!well-known).*" = {
      priority = 102;
      extraConfig = ''
        deny all;
      '';
    };
    extraConfig = ''
      index index.php;
      access_log /var/log/nginx/pelican.app-access.log;
      error_log /var/log/nginx/pelican.app-error.log warn;
      add_header X-Content-Type-Options "nosniff";
      add_header X-XSS-Protection "1; mode=block";
      add_header X-Robots-Tag "none";
      add_header X-Frame-Options "DENY";
      add_header Referrer-Policy "same-origin";
      add_header Content-Security-Policy "frame-ancestors 'self'";
      client_max_body_size 100m;
      client_body_timeout 120s;
      sendfile off;
    '';
  };
}
