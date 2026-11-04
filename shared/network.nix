{ lib, ... }:

{
  networking.networkmanager.enable = lib.mkDefault true;
  networking.networkmanager.dns = lib.mkDefault "none";
  networking.dhcpcd.extraConfig = "nohook resolv.conf";
  networking.resolvconf.enable = lib.mkDefault true;
  networking.nameservers = lib.mkDefault [
    "40.160.23.89"
    "1.1.1.1"
    "8.8.8.8"
  ];
}
