{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."spotify.pulsar.ltd-http" = {
    serverName = "spotify.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."spotify.pulsar.ltd" = {
    serverName = "spotify.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."= /api" = {
      priority = 100;
      extraConfig = ''
        return 301 /api/;
      '';
    };
    locations."^~ /api/" = {
      priority = 101;
      proxyPass = "http://127.0.0.1:2942";
      extraConfig = ''
        rewrite ^/api/?(.*)$ /$1 break;
      '';
    };
    locations."^~ /oauth/" = {
      priority = 102;
      proxyPass = "http://127.0.0.1:2942";
    };
    locations."= /me" = {
      priority = 103;
      proxyPass = "http://127.0.0.1:2942/me";
    };
    locations."= /version" = {
      priority = 104;
      proxyPass = "http://127.0.0.1:2942/version";
    };
    locations."^~ /accounts" = {
      priority = 105;
      proxyPass = "http://127.0.0.1:2942";
    };
    locations."^~ /spotify/" = {
      priority = 106;
      proxyPass = "http://127.0.0.1:2942";
    };
    locations."^~ /global/" = {
      priority = 107;
      proxyPass = "http://127.0.0.1:2942";
    };
    locations."= /global/preferences" = {
      priority = 108;
      proxyPass = "http://127.0.0.1:2942/global/preferences";
      extraConfig = ''
        proxy_set_header Accept-Encoding "";
        sub_filter_once on;
        sub_filter_types application/json;
        sub_filter '{' '[{';
        sub_filter '}' '}]';
      '';
    };
    locations."^~ /users/" = {
      priority = 109;
      proxyPass = "http://127.0.0.1:2942";
    };
    locations."^~ /socket.io/" = {
      priority = 110;
      proxyPass = "http://127.0.0.1:2942";
    };
    locations."/" = {
      priority = 111;
      proxyPass = "http://127.0.0.1:4685";
    };
    extraConfig = ''
      client_max_body_size 20m;
      add_header X-Spotify-Vhost 1 always;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_hide_header Content-Security-Policy;
      proxy_hide_header Content-Security-Policy-Report-Only;
      add_header Content-Security-Policy "default-src 'self' https: data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval' https:; style-src 'self' 'unsafe-inline' https:; img-src 'self' https: data: blob:; font-src 'self' https: data:; connect-src 'self' https: wss:; frame-ancestors 'none';" always;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_cookie_path / "/; Secure; SameSite=Lax";
      proxy_connect_timeout 10s;
      proxy_send_timeout 60s;
      proxy_read_timeout 60s;
      add_header X-Frame-Options SAMEORIGIN;
      add_header X-Content-Type-Options nosniff;
      add_header X-XSS-Protection "1; mode=block";
      add_header Referrer-Policy no-referrer-when-downgrade;
    '';
  };
}
