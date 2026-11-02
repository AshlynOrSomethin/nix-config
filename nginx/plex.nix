{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."plex.pulsar.ltd-http" = {
    serverName = "plex.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = plex.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://plex.pulsar.ltd$request_uri;
    '';
  };
  services.nginx.virtualHosts."plex.pulsar.ltd" = {
    serverName = "plex.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:32400";
    };
  };
}
