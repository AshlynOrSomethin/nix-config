{
  imports = [
    ./hardware-configuration.nix
    ./mounts.nix
    ./docker.nix
    ./system.nix
    ./locale.nix
    ./network.nix
    ./sshfs.nix
    ./services.nix
    ./packages.nix
    ./programs.nix
    ./shells.nix
    ./virtualization.nix
    ./proxmox.nix
    ./uutils.nix
    ./pelican.nix
#    ./vscode.nix
  ];
}
