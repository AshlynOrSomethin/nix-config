{
  networking.hostName = "ovhserver";
  networking.nameservers = [ "213.186.33.99" ];
  networking.networkmanager.ensureProfiles.profiles.ovh-uplink = {
    connection = {
      id = "ovh-uplink";
      type = "ethernet";
      interface-name = "enp8s0f0np0";
      autoconnect = true;
    };
    ipv4.method = "auto";
    ipv6.method = "auto";
  };
}
