{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."jellyvue.pulsar.ltd-http" = {
    serverName = "jellyvue.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = jellyvue.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://jellyvue.pulsar.ltd$request_uri;
    '';
  };
  services.nginx.virtualHosts."jellyvue.pulsar.ltd" = {
    serverName = "jellyvue.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:8084";
    };
  };
}
