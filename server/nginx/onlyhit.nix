{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."pulsar.ltd-http" = {
    serverName = "pulsar.ltd";
    serverAliases = [ "www.pulsar.ltd" "dashboard.pulsar.ltd" "home.pulsar.ltd" ];
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."pulsar.ltd" = {
    http2 = true;
    serverName = "pulsar.ltd";
    serverAliases = [ "www.pulsar.ltd" "dashboard.pulsar.ltd" "home.pulsar.ltd" ];
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:1222";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      '';
    };
    extraConfig = ''
      ssl_session_timeout 10m;
    '';
  };
}
