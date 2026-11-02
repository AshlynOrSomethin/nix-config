{ config, lib, pkgs, inputs, ... }:
{
  home.stateVersion = "26.05";  # match your NixOS stateVersion
  imports = [
      ./zshrc.nix
      ./sops.nix
      ];

  home.packages = with pkgs; [
    topgrade
  ];

  services.udiskie = {
    enable = true;
  };
}
