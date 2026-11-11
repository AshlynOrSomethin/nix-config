{ lib, ... }:

{
  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
    };
    systemd-boot.enable = false;
    efi.canTouchEfiVariables = true;
  };

  users.users.ashlyn = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... ashlyn@nixos"
    ];
    extraGroups = lib.mkAfter [ "docker" "podman" ];
  };
}
