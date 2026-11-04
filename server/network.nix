{
  networking.firewall.enable = false;
  networking.hostName = "server";
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "none";
  networking.networkmanager.ensureProfiles.profiles = {
    vmbr0 = {
      connection = {
        id = "vmbr0";
        type = "bridge";
        interface-name = "vmbr0";
        autoconnect = true;
        autoconnect-ports = 1;
        autoconnect-priority = 100;
      };
      bridge = {
        mac-address = "04:7c:16:db:b5:66";
        stp = false;
      };
      ipv4 = {
        method = "manual";
        address1 = "192.168.1.2/24,192.168.1.1";
      };
      ipv6.method = "auto";
    };
    vmbr0-uplink = {
      connection = {
        id = "vmbr0-uplink";
        type = "ethernet";
        interface-name = "enp4s0";
        controller = "vmbr0";
        port-type = "bridge";
        autoconnect = true;
        autoconnect-priority = 100;
      };
    };
  };
  networking.dhcpcd.extraConfig = "nohook resolv.conf";
  networking.resolvconf.enable = true;
  networking.nameservers = [
    "40.160.23.89"
    "1.1.1.1"
    "8.8.8.8"
  ];
}
