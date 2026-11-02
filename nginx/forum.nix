{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."forumtestsite.pulsar.ltd-http" = {
    serverName = "forumtestsite.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = forumtestsite.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."forumtestsite.pulsar.ltd" = {
    http2 = true;
    serverName = "forumtestsite.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    extraConfig = ''
      ssl_protocols TLSv1.2 TLSv1.3;
      ssl_prefer_server_ciphers on;
      ssl_ciphers HIGH:!aNULL:!MD5;
      return 302 https://www.youtube.com/watch?v=dQw4w9WgXcQ;
      access_log /var/log/nginx/forumtestsite.pulsar.ltd.access.log;
      error_log /var/log/nginx/forumtestsite.pulsar.ltd.error.log;
    '';
  };
}
