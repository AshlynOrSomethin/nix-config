{
  imports = [
    ../shared
    ./hardware-configuration.nix
    ./network.nix
    ./services.nix
    ../server/system.nix
    ../server/packages.nix
    ../server/programs.nix
    ./virtualization.nix
  ];
}
