{
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      MAILADDR root
      ARRAY /dev/md/jellyraid UUID=28738c53:c223ee60:527baf92:b4ce484f
    '';
  };

  fileSystems."/media/sda" = {
    device = "/dev/disk/by-uuid/c49c46b9-8989-4177-b62a-cb51496c90c2";
    fsType = "xfs";
  };

  fileSystems."/media/md" = {
    device = "/dev/disk/by-uuid/9e53479a-4eda-494c-bd25-b6b542822568";
    fsType = "xfs";
    options = [ "nofail" ];
  };

  systemd.tmpfiles.rules = [
    "d /etc/nixos 0755 ashlyn users -"
  ];
}
