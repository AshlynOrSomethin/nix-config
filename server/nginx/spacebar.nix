{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."spacebar.pulsar.ltd" = {
    serverName = "spacebar.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      return = "410";
    };
    locations."/.well-known/spacebar" = {
      priority = 101;
      extraConfig = ''
        add_header Access-Control-Allow-Origin *;
        return 200 '{"api": "https://api.spacebar.chat/api/v9"}';
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy no-referrer-when-downgrade;
      '';
    };
  };
  services.nginx.virtualHosts."spacebar.pulsar.ltd-http" = {
    serverName = "spacebar.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = spacebar.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 404;
    '';
  };
}
