{
  services.nginx.virtualHosts."pipeweaver.pulsar.ltd-http" = {
    serverName = "pipeweaver.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };

  services.nginx.virtualHosts."pipeweaver.pulsar.ltd" = {
    serverName = "pipeweaver.pulsar.ltd";
    http2 = true;
    onlySSL = true;
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    sslTrustedCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    basicAuthFile = "/var/lib/nginx/pipeweaver.htpasswd";
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "http://192.168.1.3:14565";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Authorization "";
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
