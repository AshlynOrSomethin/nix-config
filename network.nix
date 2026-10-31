{
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "none";
  networking.dhcpcd.extraConfig = "nohook resolv.conf";
  networking.resolvconf.enable = true;
  networking.nameservers = [
    "40.160.23.89"
    "1.1.1.1"
    "8.8.8.8"
  ];
}
