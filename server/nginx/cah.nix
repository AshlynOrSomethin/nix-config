{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."cah.pulsar.ltd-http" = {
    serverName = "cah.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = cah.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      if ($host = heimdall.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://cah.pulsar.ltd$request_uri;
    '';
  };
  services.nginx.virtualHosts."cah.pulsar.ltd" = {
    serverName = "cah.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslTrustedCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://127.0.0.1:8819/";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_set_header Host 127.0.0.1:8819;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Real-IP $remote_addr;
        client_max_body_size 512M;
      '';
    };
    extraConfig = ''
      ssl_prefer_server_ciphers on;
      ssl_protocols TLSv1.3 TLSv1.2;
      ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256';
      ssl_ecdh_curve prime256v1:secp384r1:secp521r1;
      ssl_session_cache shared:TLS:50m;
      ssl_session_timeout 1d;
      ssl_session_tickets off;
      access_log /var/log/nginx/heimdall.pulsar.ltd.access.log;
    '';
  };
}
