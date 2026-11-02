{ config, inputs, ... }:

{
  imports = [ inputs.proxmox-nixos.nixosModules.proxmox-ve ];

  nixpkgs.overlays = [ inputs.proxmox-nixos.overlays.${config.nixpkgs.hostPlatform.system} ];

  services.proxmox-ve = {
    enable = true;
    ipAddress = "192.168.1.2";
  };

  nix.settings = {
    extra-substituters = [ "https://cache.saumon.network/proxmox-nixos" ];
    extra-trusted-public-keys = [
      "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM="
    ];
  };
}
