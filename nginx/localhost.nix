{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."localhost-http" = {
    serverName = "localhost";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];
    default = true;
    locations."/" = {
      priority = 100;
      root = "${pkgs.nginx}/html";
      index = "index.html index.htm";
    };
    locations."= /50x.html" = {
      priority = 101;
      root = "${pkgs.nginx}/html";
    };
    extraConfig = ''
      error_page 500 502 503 504 /50x.html;
    '';
  };
}
