{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."php.pulsar.ltd-http" = {
    serverName = "php.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    locations."^~ /.well-known/acme-challenge/" = {
      priority = 100;
      root = "/var/www/localhost/htdocs";
    };
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."php.pulsar.ltd" = {
    http2 = true;
    serverName = "php.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    root = "/var/www/localhost/htdocs/phpmyadmin";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."~* ^/(?:setup|doc|examples|sql)/" = {
      priority = 100;
      extraConfig = ''
        deny all;
      '';
    };
    locations."~* ^/(?:vendor|libraries|templates)/" = {
      priority = 101;
      extraConfig = ''
        deny all;
      '';
    };
    locations."/" = {
      priority = 102;
      tryFiles = "$uri $uri/ /index.php?$args";
    };
    locations."~ \\.php$" = {
      priority = 103;
      extraConfig = ''
        include ${pkgs.nginx}/conf/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_index index.php;
        fastcgi_pass 127.0.0.1:9900;
      '';
    };
    locations."~ /\\." = {
      priority = 104;
      extraConfig = ''
        deny all;
      '';
    };
    extraConfig = ''
      index index.php;
      access_log /var/log/nginx/php.pulsar.ltd.access.log;
      error_log /var/log/nginx/php.pulsar.ltd.error.log;
      client_max_body_size 64m;
    '';
  };
}
