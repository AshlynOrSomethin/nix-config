{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."portainer.pulsar.ltd-http" = {
    serverName = "portainer.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."portainer.pulsar.ltd" = {
    http2 = true;
    serverName = "portainer.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "https://127.0.0.1:9444";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
    extraConfig = ''
      client_max_body_size 128M;
    '';
  };
}
