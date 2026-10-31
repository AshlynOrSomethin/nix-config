{
  description = "ashlyn's NixOS config";

  inputs = {

    # No nixpkgs.follows here, on purpose, so the kernel patches match the cache.
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

    cosmic-greeter = {
      url = "github:pop-os/cosmic-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dux-files = {
      url = "github:duxlabs-dev/dux-files";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fresh = {
      url = "github:sinelaw/fresh";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";           # branch must match your nixpkgs
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jj = {
      url = "github:jj-vcs/jj";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:niri-wm/niri";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-your-shell = {
      url = "github:mercury/nix-your-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    prismlauncher = {
        url = "github:prismlauncher/PrismLauncher";
        inputs.nixpkgs.follows = "nixpkgs";
    };

    qylock = {
      url = "github:Darkkal44/qylock";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rofi-themes = {
      url = "github:adi1090x/rofi";
      flake = false;
    };

    satty = {
      url = "github:Satty-org/Satty/main";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { chaotic, dms, dux-files, home-manager, niri, nix-flatpak, nixpkgs, qylock, self, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.ashlyn = import ./home/home.nix;
          home-manager.backupFileExtension = "bak";
        }
        dms.nixosModules.dank-material-shell
        qylock.nixosModules.default
        chaotic.nixosModules.nyx-cache
        chaotic.nixosModules.nyx-overlay
        chaotic.nixosModules.nyx-registry
        nix-flatpak.nixosModules.nix-flatpak
      ];
    };
  };
}
