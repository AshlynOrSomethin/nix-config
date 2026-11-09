{ lib, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.sbctl ];

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
