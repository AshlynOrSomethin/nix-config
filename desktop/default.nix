{
  imports = [
    ../shared
    ../shared/puressh.nix
    ./hardware-configuration.nix
    ./boot.nix
    ./services.nix
    ./packages.nix
    ./prores.nix
    ./home/gaming.nix
    ./shells.nix
    ./virtualization.nix
    ./fonts.nix
    ./davinci.nix
    ./home/flatpak.nix
    ./home/vscode.nix
  ];
}
