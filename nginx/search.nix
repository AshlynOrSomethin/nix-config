{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."search.pulsar.ltd-http" = {
    serverName = "search.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."search.pulsar.ltd" = {
    http2 = true;
    serverName = "search.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    sslTrustedCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:8842";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_read_timeout 300;
        proxy_send_timeout 300;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
      '';
    };
    extraConfig = ''
      ssl_protocols TLSv1.3 TLSv1.2;
      ssl_prefer_server_ciphers on;
      ssl_session_cache shared:TLS:50m;
      ssl_session_timeout 1d;
      ssl_session_tickets off;
      access_log /var/log/nginx/search.pulsar.ltd.access.log;
      error_log /var/log/nginx/search.pulsar.ltd.error.log warn;
      client_max_body_size 512M;
    '';
  };
}
