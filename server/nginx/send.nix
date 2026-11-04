{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."send.pulsar.ltd" = {
    serverName = "send.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:1443";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_http_version 1.1;
      '';
    };
    extraConfig = ''
      keepalive_timeout 70;
    '';
  };
}
