{ config, pkgs, ... }:

{
  services.nginx.virtualHosts."archive.pulsar.ltd" = {
    serverName = "archive.pulsar.ltd";
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    root = "/var/www/cloudgang";
    http2 = false;
    onlySSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 443; ssl = true; }
      { addr = "[::]"; port = 443; ssl = true; }
    ];
    locations."/" = {
      priority = 100;
      tryFiles = "$uri $uri/ /index.html";
    };
    locations."~ \"^/(admin_chat|announcements|rules|ticket_support|welcoming|roles|close_friends|quotes|general|games|bot_commands|therapy_session|no_mic|tiktok|poems|scrunchie_talk|foodies|pet_appreciation|boba|alcohol_spam|anime|face_reveal|music|fan_arts|marriage_proposals|memes|media|movie_suggestion|admin_commands|tickets|caught_in_4k|dyno_updates)$\"" = {
      priority = 101;
      tryFiles = "$uri $uri/ /$1.html";
    };
    locations."/lunar" = {
      priority = 102;
      root = "/var/www/lunar.exe";
      index = "lunar.exe";
      tryFiles = "$uri $uri/ /lunar.exe";
    };
    extraConfig = ''
      index index.html;
    '';
  };
  services.nginx.virtualHosts."archive.pulsar.ltd-http" = {
    serverName = "archive.pulsar.ltd";
    http2 = false;
    listen = [
      { addr = "0.0.0.0"; port = 80; ssl = false; }
      { addr = "[::]"; port = 80; ssl = false; }
    ];
    extraConfig = ''
      if ($host = archive.pulsar.ltd) {
        return 301 https://$host$request_uri;
      }
      return 301 https://archive.pulsar.ltd$request_uri;
    '';
  };
}
