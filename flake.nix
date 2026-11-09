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

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jj = {
      url = "github:jj-vcs/jj";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # niri = {
    #   url = "github:niri-wm/niri";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    umbriel.url = "github:noctalia-dev/umbriel";

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

    # Follow upstream; the rebuild helper updates the locked revision each time.
    pipeweaver = {
      url = "github:pipeweaver/pipeweaver";
      flake = false;
    };
    
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

    serein = {
      url = "github:ViceVerse-cz/Serein";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pelican-panel = {
      url = "github:mpeterson2/nix-pelican-panel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";

    vscode-server.url = "github:nix-community/nixos-vscode-server";

  };

  outputs = { chaotic, dms, dux-files, home-manager, nix-flatpak, nixpkgs, qylock, vscode-server, ... }@inputs:
    let
      mkHost = { host, home, configuration, extraModules ? [ ] }:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit host inputs; };
          modules = [
            configuration
            home-manager.nixosModules.home-manager
          ] ++ extraModules ++ [
            {
              nixpkgs.overlays = [
                (final: prev: {
                  pipeweaver = final.callPackage ./packages/pipeweaver.nix {
                    src = inputs.pipeweaver;
                  };
                })
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users.ashlyn = import home;
              home-manager.backupFileExtension = "bak";
            }
            chaotic.nixosModules.nyx-cache
            chaotic.nixosModules.nyx-overlay
            chaotic.nixosModules.nyx-registry
          ];
        };

      desktop = mkHost {
        host = "desktop";
        configuration = ./desktop/default.nix;
        home = ./desktop/home/home.nix;
        extraModules = [
          inputs.lanzaboote.nixosModules.lanzaboote
          inputs.umbriel.nixosModules.default
          dms.nixosModules.dank-material-shell
          qylock.nixosModules.default
          nix-flatpak.nixosModules.nix-flatpak
        ];
      };

      server = mkHost {
        host = "server";
        configuration = ./server/default.nix;
        home = ./server/home/home.nix;
        extraModules = [
          vscode-server.nixosModules.default
          {
            services.vscode-server.enable = true;
          }
        ];
      };
    in
    {
      nixosConfigurations = {
        inherit desktop server;
        nixos = desktop;
      };
    };
}
