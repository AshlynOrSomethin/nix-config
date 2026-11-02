{
  services.nginx.virtualHosts."proxmox.pulsar.ltd-http" = {
    serverName = "proxmox.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      return 301 https://$host$request_uri;
    '';
  };

  services.nginx.virtualHosts."proxmox.pulsar.ltd" = {
    serverName = "proxmox.pulsar.ltd";
    http2 = true;
    onlySSL = true;
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      proxyPass = "https://127.0.0.1:8006";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        # Proxmox generates its own backend certificate.
        proxy_ssl_verify off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
    extraConfig = ''
      client_max_body_size 0;
    '';
  };
}
