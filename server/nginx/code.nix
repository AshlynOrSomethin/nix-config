{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."code.pulsar.ltd-http" = {
    serverName = "code.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."code.pulsar.ltd" = {
    serverName = "code.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:8443";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
      '';
    };
    extraConfig = ''
      gzip off;
      client_max_body_size 0;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_http_version 1.1;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
      proxy_buffering off;
    '';
  };
}
