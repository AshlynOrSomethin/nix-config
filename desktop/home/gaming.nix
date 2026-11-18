{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-cachyos-bin_x86_64_v3 ];
  };
  programs.gamemode.enable = true;
}
