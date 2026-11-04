{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."matrix.pulsar.ltd" = {
    serverName = "matrix.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 8448; ssl = false; extraParameters = [ "default_server" ]; }
      { addr = "[::]"; port = 8448; ssl = false; extraParameters = [ "default_server" ]; }
      { addr = "[::]"; port = 443; ssl = true; extraParameters = [ "ipv6only=on" ]; }
      { addr = "0.0.0.0"; port = 443; ssl = true; }
    ];
    locations."~ ^(/_matrix|/_synapse/client)" = {
      priority = 100;
      proxyPass = "http://localhost:8008";
      extraConfig = ''
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host:$server_port;
        client_max_body_size 50M;
        proxy_http_version 1.1;
      '';
    };
    locations."^~ /.well-known/" = {
      priority = 101;
      root = "/usr/share/nginx/html";
      tryFiles = "$uri $uri/ =404";
      extraConfig = ''
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization';
        if ($request_method = 'OPTIONS') {
          add_header 'Access-Control-Allow-Origin' '*';
          add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
          add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization';
          add_header 'Content-Length' 0;
          add_header 'Access-Control-Max-Age' 3600;
          return 204;
          add_header X-Frame-Options SAMEORIGIN;
          add_header X-Content-Type-Options nosniff;
          add_header X-XSS-Protection "1; mode=block";
          add_header Referrer-Policy no-referrer-when-downgrade;
        }
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy no-referrer-when-downgrade;
      '';
    };
  };
}
