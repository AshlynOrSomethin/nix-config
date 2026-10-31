{ pkgs, lib, ... }:

{
  boot.supportedFilesystems.zfs = lib.mkForce false;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_cachyos-lto-znver4;

  nixpkgs.overlays = [ (final: prev: {
    inherit (prev.lixPackageSets.stable)
      nixpkgs-review
      nix-eval-jobs
      nix-fast-build
      colmena;
  }) ];
  nixpkgs.config.allowUnfree = true;

  nix.package = pkgs.lixPackageSets.stable.lix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users."ashlyn" = {
    isNormalUser = true;
    description = "ashlyn";
    extraGroups = [ "networkmanager" "wheel" "vboxusers" ];
    shell = pkgs.zsh;
  };

  system.stateVersion = "26.05";
}
