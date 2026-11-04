{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."roam.pulsar.ltd-http" = {
    serverName = "roam.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = roam.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."roam.pulsar.ltd" = {
    serverName = "roam.pulsar.ltd";
    root = "/var/www/roam/dist/tmdb-streamer";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      tryFiles = "$uri $uri/ /index.html";
    };
    locations."~* \\.(?:manifest|appcache|html?|xml|json)$" = {
      priority = 101;
      extraConfig = ''
        add_header Cache-Control "no-cache";
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy no-referrer-when-downgrade;
      '';
    };
    locations."~* \\.(?:css|js|woff2?|ttf|otf|eot|svg|jpg|jpeg|png|gif|ico)$" = {
      priority = 102;
      extraConfig = ''
        add_header Cache-Control "max-age=31536000, public";
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy no-referrer-when-downgrade;
      '';
    };
    extraConfig = ''
      index index.html;
      ssl_protocols TLSv1.2 TLSv1.3;
      ssl_ciphers HIGH:!aNULL:!MD5;
      auth_basic "Restricted Area";
      auth_basic_user_file /etc/nginx/.htpasswd;
      access_log /var/log/nginx/roam.pulsar.ltd.access.log;
      error_log /var/log/nginx/roam.pulsar.ltd.error.log;
    '';
  };
}
