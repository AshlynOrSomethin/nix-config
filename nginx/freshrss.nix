{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."freshrss.pulsar.ltd" = {
    http2 = true;
    serverName = "freshrss.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    root = "/usr/share/webapps/freshrss/1.28.1/htdocs";
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      tryFiles = "$uri $uri/ /index.php?$query_string";
    };
    locations."~ \\.php$" = {
      priority = 101;
      extraConfig = ''
        include ${pkgs.nginx}/conf/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_index index.php;
        fastcgi_pass 127.0.0.1:9900;
      '';
    };
    extraConfig = ''
      index index.php index.html;
    '';
  };
}
