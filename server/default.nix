{
  imports = [
    ../shared
    ./hardware-configuration.nix
    ./mounts.nix
    ./docker.nix
    ./system.nix
    ./network.nix
    ./services.nix
    ./packages.nix
    ./programs.nix
    ./virtualization.nix
    ./proxmox.nix
    ./home/qbit.nix
    ./vaultwarden-backup/vaultwarden-backup.nix
    ./pelican.nix
  ];
}
