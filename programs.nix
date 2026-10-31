{ pkgs, inputs, ... }:

{
  programs.qylock = {
    enable = true;
    theme = "pixel-night-city";
    quickshell.enable = false;
  };

  programs.niri.enable = true;
  programs.niri.package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
  programs.dank-material-shell = {
    enable = true;
    enableCalendarEvents = false;
    systemd.enable = true;
  };
  programs.dux-search.enable = true;
  programs.dux-search.systemd.enable = true;
}
