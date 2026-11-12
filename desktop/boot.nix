{ lib, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.sbctl ];

  boot.initrd.kernelModules = [ "amdgpu" ];

  services.bootvine.enable = true;
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet"
    "rd.udev.log_level=3"
    "rd.systemd.show_status=auto"
  ];

  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
