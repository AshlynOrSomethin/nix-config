{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."jellyfin.pulsar.ltd-http" = {
    serverName = "jellyfin.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = jellyfin.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://jellyfin.pulsar.ltd$request_uri;
    '';
  };
  services.nginx.virtualHosts."jellyfin.pulsar.ltd" = {
    serverName = "jellyfin.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:8096";
    };
  };
}
