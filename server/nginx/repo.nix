{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."repo.pulsar.ltd-http" = {
    serverName = "repo.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = repo.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://$host$request_uri;
    '';
  };
  services.nginx.virtualHosts."repo.pulsar.ltd" = {
    serverName = "repo.pulsar.ltd";
    root = "/var/www/repo";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      extraConfig = ''
        autoindex off;
        fancyindex on;
        fancyindex_exact_size off;
        fancyindex_localtime on;
        fancyindex_header "/Nginx-Fancyindex/header.html";
        fancyindex_footer "/Nginx-Fancyindex/footer.html";
        fancyindex_ignore "Nginx-Fancyindex";
        fancyindex_ignore "examplefile.html";
      '';
    };
    locations."~* \\.(php|cgi|pl|py|sh)$" = {
      priority = 101;
      extraConfig = ''
        deny all;
      '';
    };
    extraConfig = ''
      ssl_protocols TLSv1.2 TLSv1.3;
      ssl_prefer_server_ciphers on;
      ssl_ciphers HIGH:!aNULL:!MD5;
      access_log /var/log/nginx/repo.pulsar.ltd.access.log;
      error_log /var/log/nginx/repo.pulsar.ltd.error.log;
    '';
  };
}
