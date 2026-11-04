{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."monopoly.pulsar.ltd-http" = {
    serverName = "monopoly.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = monopoly.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://$server_name$request_uri;
    '';
  };
  services.nginx.virtualHosts."monopoly.pulsar.ltd" = {
    http2 = true;
    serverName = "monopoly.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "https://127.0.0.1:6904";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header Referer $http_referer;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
    extraConfig = ''
      proxy_set_header Referer $http_referer;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Real-Port $remote_port;
      proxy_set_header X-Forwarded-Host $host:$remote_port;
      proxy_set_header X-Forwarded-Server $host;
      proxy_set_header X-Forwarded-Port $remote_port;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Ssl on;
    '';
  };
}
