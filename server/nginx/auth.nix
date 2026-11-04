{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."auth.pulsar.ltd-http" = {
    serverName = "auth.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."auth.pulsar.ltd" = {
    http2 = true;
    serverName = "auth.pulsar.ltd";
    root = "/var/www/2fauth/public";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    sslTrustedCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      tryFiles = "$uri $uri/ /index.php?$query_string";
    };
    locations."~ \\.php$" = {
      priority = 101;
      extraConfig = ''
        include ${pkgs.nginx}/conf/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        fastcgi_pass 127.0.0.1:9900;
        fastcgi_read_timeout 300;
      '';
    };
    locations."~ /\\.(?!well-known).*" = {
      priority = 102;
      extraConfig = ''
        deny all;
      '';
    };
    locations."= /favicon.ico" = {
      priority = 103;
      extraConfig = ''
        access_log off;
        log_not_found off;
      '';
    };
    locations."= /robots.txt" = {
      priority = 104;
      extraConfig = ''
        access_log off;
        log_not_found off;
      '';
    };
    extraConfig = ''
      index index.php;
      ssl_protocols TLSv1.2 TLSv1.3;
      ssl_prefer_server_ciphers off;
      charset utf-8;
      add_header X-Frame-Options "DENY" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
      add_header X-XSS-Protection "1; mode=block";
    '';
  };
}
