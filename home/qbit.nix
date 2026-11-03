{ lib, pkgs, ... }:

{
  xdg.configFile."qBittorrent/qBittorrent.conf".text = lib.generators.toINI { } {
    LegalNotice.Accepted = true;
    Preferences = {
      "WebUI\\Address" = "127.0.0.1";
      "WebUI\\Port" = 8085;
      "WebUI\\AlternativeUIEnabled" = true;
      "WebUI\\RootFolder" = "${pkgs.vuetorrent}/share/vuetorrent";
    };
  };
}
