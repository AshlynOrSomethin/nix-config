{ lib, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.sbctl ];

  # Initialize graphics in the initrd so Plymouth can display the splash.
  boot.initrd.kernelModules = [ "amdgpu" ];

  boot.plymouth = {
    enable = true;
    theme = "bgrt";
  };
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet"
    "rd.udev.log_level=3"
    "rd.systemd.show_status=auto"
  ];

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
