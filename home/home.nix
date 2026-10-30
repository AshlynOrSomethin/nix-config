{ config, lib, pkgs, inputs, ... }:
{
  home.stateVersion = "26.05";  # match your NixOS stateVersion
  imports = [
      ./zshrc.nix
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
    vesktop
    (discord.override {
      withOpenASAR = true;
      withVencord = true;
    })
    inputs.prismlauncher.packages.${pkgs.stdenv.hostPlatform.system}.prismlauncher
    topgrade
    papirus-icon-theme
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

  services.flameshot = {
    enable = true;
    settings.General = {
      savePath = "${config.home.homeDirectory}/Screenshots";
      disabledTrayIcon = true;
      showStartupLaunchMessage = false;
      saveAsFileExtension = ".png";
      showDesktopNotification = true;
      showAbortNotification = false;
      showHelp = false;
      showSidePanelButton = true;
      useX11LegacyScreenshot = true;
      captureActiveMonitor = false;
      uiColor = "#740096";
      contrastUiColor = "#270032";
      drawColor = "#ff0000";
    };
  };

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
