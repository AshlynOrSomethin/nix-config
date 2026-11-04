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
      proxyPass = "http://127.0.0.1:3001";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_pass_request_headers on;
        add_header Last-Modified $date_gmt;
        add_header Cache-Control 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0';
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Host $remote_addr;
        proxy_no_cache 1;
        proxy_cache_bypass 1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy no-referrer-when-downgrade;
      '';
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
