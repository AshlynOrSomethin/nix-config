{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."git.pulsar.ltd" = {
    http2 = true;
    serverName = "git.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslTrustedCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://192.168.1.2:3005";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_read_timeout 300;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
      '';
    };
    extraConfig = ''
      client_max_body_size 512M;
    '';
  };
}
