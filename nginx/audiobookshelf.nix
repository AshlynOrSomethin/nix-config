{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."audiobookshelf.pulsar.ltd" = {
    http2 = true;
    serverName = "audiobookshelf.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:13378";
      extraConfig = ''
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_http_version 1.1;
        proxy_redirect http:// https://;
        client_max_body_size 10240M;
      '';
    };
    extraConfig = ''
      ssl_protocols TLSv1.2 TLSv1.3;
      access_log /var/log/nginx/audiobookshelf.access.log;
      error_log /var/log/nginx/audiobookshelf.error.log;
    '';
  };
}
