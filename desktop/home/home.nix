{ config, lib, pkgs, inputs, ... }:
let
  satty = pkgs.satty.overrideAttrs (old: {
    version = "unstable-${inputs.satty.shortRev}";
    src = inputs.satty;
    cargoDeps = pkgs.rustPlatform.importCargoLock {
      lockFile = "${inputs.satty}/Cargo.lock";
    };
    checkInputs = (old.checkInputs or []) ++ [ pkgs.libxkbcommon ];
  });
in
{
  home.stateVersion = "26.05";  # match your NixOS stateVersion
  imports = [
      ./zshrc.nix
      ./sops.nix
      ../niri.nix
      ./ghostty.nix
      inputs.dux-files.homeModules.dux-files
      ];

  programs.rofi.enable = true;

  programs.dux-files = {
    enable = true;
    systemd.enable = true;
    portal.enable = true;
  };

  home.packages = with pkgs; [
    qbittorrent
    bitwarden-desktop
    vesktop
    (discord.override {
      withOpenASAR = true;
      withVencord = true;
    })
    inputs.prismlauncher.packages.${pkgs.stdenv.hostPlatform.system}.prismlauncher
    topgrade
    satty
    papirus-icon-theme
    (writeShellApplication {
      name = "screenshot-annotate";
      runtimeInputs = [
        coreutils
        inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell
        satty
      ];
      text = ''
        screenshot=$(mktemp --suffix=.png)
        trap 'rm -f "$screenshot"' EXIT

        dms screenshot --stdout --no-confirm > "$screenshot"
        if [[ ! -s "$screenshot" ]]; then
          exit 0
        fi

        mkdir -p "$HOME/Screenshots"
        satty --filename "$screenshot" \
          --output-filename "$HOME/Screenshots/Screenshot-%Y-%m-%d-%H-%M-%S.png"
      '';
    })
    (writeShellScriptBin "rofi-launcher" ''
      exec rofi -show drun -theme "$HOME/.config/rofi/launchers/type-7/style-4.rasi"
    '')
  ];

  xdg.configFile = {
    "rofi/launchers/type-7".source = "${inputs.rofi-themes}/files/launchers/type-7";
    "rofi/colors".source           = "${inputs.rofi-themes}/files/colors";
    "Code/User/settings.json".text = builtins.toJSON {
      "terminal.integrated.fontFamily" = "'JetBrainsMono Nerd Font'";
      "workbench.colorTheme" = "Modern Purple Theme Dark";
      "workbench.colorCustomizations" = {
        "terminal.background" = "#0f0028";
        "terminal.foreground" = "#dddddd";
        "terminal.selectionBackground" = "#37323c";
        "terminalCursor.foreground" = "#8c91fa";
        "terminal.ansiBlack" = "#230046";
        "terminal.ansiRed" = "#7d1625";
        "terminal.ansiGreen" = "#337e6f";
        "terminal.ansiYellow" = "#7f6f49";
        "terminal.ansiBlue" = "#4f4a7f";
        "terminal.ansiMagenta" = "#5a3f7f";
        "terminal.ansiCyan" = "#58777f";
        "terminal.ansiWhite" = "#736e7d";
        "terminal.ansiBrightBlack" = "#372d46";
        "terminal.ansiBrightRed" = "#e05167";
        "terminal.ansiBrightGreen" = "#52e0c4";
        "terminal.ansiBrightYellow" = "#e0c386";
        "terminal.ansiBrightBlue" = "#8e87e0";
        "terminal.ansiBrightMagenta" = "#a776e0";
        "terminal.ansiBrightCyan" = "#9ad4e0";
        "terminal.ansiBrightWhite" = "#8c91fa";
      };
    };
  };

  home.activation.createScreenshotDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/Screenshots"
  '';

  services.udiskie = {
    enable = true;
    settings = {
      # workaround for
      # https://github.com/nix-community/home-manager/issues/632
      program_options = {
        file_manager = "dfiles";
      };
    };
  };
}
