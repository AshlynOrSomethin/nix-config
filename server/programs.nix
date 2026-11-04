{ pkgs, inputs, ... }:

{
  programs.nix-ld.enable = true;
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

}
