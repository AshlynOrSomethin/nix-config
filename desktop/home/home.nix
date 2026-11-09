{ config, lib, pkgs, inputs, ... }:
{
  home.stateVersion = "26.05";  # match your NixOS stateVersion
  imports = [
      ./zshrc.nix
      ./sops.nix
      # ../niri.nix
      inputs.umbriel.homeModules.default
      ./ghostty.nix
      inputs.dux-files.homeModules.dux-files
      ];

  programs.umbriel = {
    enable = true;
    settings = {
      layout = {
        mode = "scrolling";
        gap = 10;
        extent_presets = [ 0.33333 0.5 0.66667 ];
        scrolling.default_extent_fraction = 0.5;
      };

      input.cursor = {
        theme = "Breeze-Adapta-Cursor";
        size = 20;
      };

      keybinds = {
        "Mod+Shift+Slash" = "cheatsheet-toggle";

        "Mod+T" = "spawn ghostty";
        "Mod+R" = "spawn rofi-launcher";
        "Super+Alt+L" = "spawn swaylock";
        "Super+Alt+S" = {
          action = "spawn pkill orca || exec orca";
          allow_when_locked = true;
        };

        "XF86AudioRaiseVolume" = {
          action = "spawn wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0";
          allow_when_locked = true;
        };
        "XF86AudioLowerVolume" = {
          action = "spawn wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-";
          allow_when_locked = true;
        };
        "XF86AudioMute" = {
          action = "spawn wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          allow_when_locked = true;
        };
        "XF86AudioMicMute" = {
          action = "spawn wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          allow_when_locked = true;
        };
        "XF86AudioPlay" = {
          action = "spawn playerctl play-pause";
          allow_when_locked = true;
        };
        "XF86AudioStop" = {
          action = "spawn playerctl stop";
          allow_when_locked = true;
        };
        "XF86AudioPrev" = {
          action = "spawn playerctl previous";
          allow_when_locked = true;
        };
        "XF86AudioNext" = {
          action = "spawn playerctl next";
          allow_when_locked = true;
        };
        "XF86MonBrightnessUp" = {
          action = "spawn brightnessctl --class=backlight set +10%";
          allow_when_locked = true;
        };
        "XF86MonBrightnessDown" = {
          action = "spawn brightnessctl --class=backlight set 10%-";
          allow_when_locked = true;
        };

        "Mod+O" = { action = "overview-toggle"; repeat = false; };
        "Mod+Q" = { action = "window-close"; repeat = false; };

        "Mod+Left" = "window-focus-left";
        "Mod+Right" = "window-focus-right";
        "Mod+Down" = "window-focus-down";
        "Mod+Up" = "window-focus-up";
        "Mod+H" = "window-focus-left";
        "Mod+J" = "window-focus-down";
        "Mod+K" = "window-focus-up";
        "Mod+L" = "window-focus-right";

        "Mod+Ctrl+Left" = "column-move-left";
        "Mod+Ctrl+Down" = "window-move-down";
        "Mod+Ctrl+Up" = "window-move-up";
        "Mod+Ctrl+Right" = "column-move-right";
        "Mod+Ctrl+H" = "column-move-left";
        "Mod+Ctrl+J" = "window-move-down";
        "Mod+Ctrl+K" = "window-move-up";
        "Mod+Ctrl+L" = "column-move-right";

        "Mod+Home" = "column-focus-first";
        "Mod+End" = "column-focus-last";
        "Mod+Ctrl+Home" = "column-move-to-first";
        "Mod+Ctrl+End" = "column-move-to-last";

        "Mod+Shift+Left" = "output-focus-left";
        "Mod+Shift+Down" = "output-focus-down";
        "Mod+Shift+Up" = "output-focus-up";
        "Mod+Shift+Right" = "output-focus-right";
        "Mod+Shift+H" = "output-focus-left";
        "Mod+Shift+J" = "output-focus-down";
        "Mod+Shift+K" = "output-focus-up";
        "Mod+Shift+L" = "output-focus-right";

        "Mod+Shift+Ctrl+Left" = "column-move-to-output-left";
        "Mod+Shift+Ctrl+Down" = "column-move-to-output-down";
        "Mod+Shift+Ctrl+Up" = "column-move-to-output-up";
        "Mod+Shift+Ctrl+Right" = "column-move-to-output-right";
        "Mod+Shift+Ctrl+H" = "column-move-to-output-left";
        "Mod+Shift+Ctrl+J" = "column-move-to-output-down";
        "Mod+Shift+Ctrl+K" = "column-move-to-output-up";
        "Mod+Shift+Ctrl+L" = "column-move-to-output-right";

        "Mod+Page_Down" = "workspace-next";
        "Mod+Page_Up" = "workspace-previous";
        "Mod+U" = "workspace-next";
        "Mod+I" = "workspace-previous";
        "Mod+Ctrl+Page_Down" = "window-move-to-workspace-next";
        "Mod+Ctrl+Page_Up" = "window-move-to-workspace-previous";
        "Mod+Ctrl+U" = "window-move-to-workspace-next";
        "Mod+Ctrl+I" = "window-move-to-workspace-previous";

        "Mod+Shift+Page_Down" = "workspace-move-down";
        "Mod+Shift+Page_Up" = "workspace-move-up";
        "Mod+Shift+U" = "workspace-move-down";
        "Mod+Shift+I" = "workspace-move-up";

        "Mod+WheelDown" = { action = "workspace-next"; cooldown_ms = 150; };
        "Mod+WheelUp" = { action = "workspace-previous"; cooldown_ms = 150; };
        "Mod+Ctrl+WheelDown" = { action = "window-move-to-workspace-next"; cooldown_ms = 150; };
        "Mod+Ctrl+WheelUp" = { action = "window-move-to-workspace-previous"; cooldown_ms = 150; };
        "Mod+WheelRight" = "window-focus-right";
        "Mod+WheelLeft" = "window-focus-left";
        "Mod+Ctrl+WheelRight" = "column-move-right";
        "Mod+Ctrl+WheelLeft" = "column-move-left";
        "Mod+Shift+WheelDown" = "window-focus-right";
        "Mod+Shift+WheelUp" = "window-focus-left";
        "Mod+Ctrl+Shift+WheelDown" = "column-move-right";
        "Mod+Ctrl+Shift+WheelUp" = "column-move-left";

        "Mod+1" = "workspace-switch 1";
        "Mod+2" = "workspace-switch 2";
        "Mod+3" = "workspace-switch 3";
        "Mod+4" = "workspace-switch 4";
        "Mod+5" = "workspace-switch 5";
        "Mod+6" = "workspace-switch 6";
        "Mod+7" = "workspace-switch 7";
        "Mod+8" = "workspace-switch 8";
        "Mod+9" = "workspace-switch 9";
        "Mod+Ctrl+1" = "window-move-to-workspace 1";
        "Mod+Ctrl+2" = "window-move-to-workspace 2";
        "Mod+Ctrl+3" = "window-move-to-workspace 3";
        "Mod+Ctrl+4" = "window-move-to-workspace 4";
        "Mod+Ctrl+5" = "window-move-to-workspace 5";
        "Mod+Ctrl+6" = "window-move-to-workspace 6";
        "Mod+Ctrl+7" = "window-move-to-workspace 7";
        "Mod+Ctrl+8" = "window-move-to-workspace 8";
        "Mod+Ctrl+9" = "window-move-to-workspace 9";

        "Mod+BracketLeft" = "window-consume-or-expel-left";
        "Mod+BracketRight" = "window-consume-or-expel-right";
        "Mod+Comma" = "window-consume-left";
        "Mod+Period" = "window-consume-or-expel-right";

        "Mod+Alt+R" = "window-cycle-primary-extent";
        "Mod+Shift+R" = "window-cycle-primary-extent-back";
        "Mod+Ctrl+Shift+R" = "window-cycle-secondary-extent";
        "Mod+Ctrl+R" = "window-set-secondary-extent 0.5";

        "Mod+F" = "window-toggle-maximize";
        "Mod+Shift+F" = "window-toggle-fullscreen";
        "Mod+M" = "window-toggle-maximize-to-edges";
        "Mod+Ctrl+F" = "window-set-primary-extent 1.0";
        "Mod+C" = "column-center";
        "Mod+Ctrl+C" = "column-center";
        "Mod+Minus" = "window-modify-primary-extent -0.1";
        "Mod+Equal" = "window-modify-primary-extent 0.1";
        "Mod+Shift+Minus" = "window-modify-secondary-extent -0.1";
        "Mod+Shift+Equal" = "window-modify-secondary-extent 0.1";

        "Mod+V" = "window-toggle-floating";
        "Mod+Shift+V" = "window-focus-switch-floating";
        "Mod+W" = "column-toggle-tabbed";

        "Print" = "spawn screenshot-annotate";
        "Ctrl+Print" = ''spawn mkdir -p "$HOME/Pictures/Screenshots" && grim "$HOME/Pictures/Screenshots/Screenshot-$(date +%Y-%m-%d-%H-%M-%S).png"'';
        "Alt+Print" = ''spawn mkdir -p "$HOME/Pictures/Screenshots" && grim -g "$(slurp)" "$HOME/Pictures/Screenshots/Window-$(date +%Y-%m-%d-%H-%M-%S).png"'';

        "Mod+Escape" = "shortcuts-inhibit-toggle";
        "Mod+Shift+E" = "session-quit";
        "Ctrl+Alt+Delete" = "session-quit";
        "Mod+Shift+P" = "dpms-off";
      };
    };
  };

  home.sessionVariables = {
    XCURSOR_THEME = "Breeze-Adapta-Cursor";
    XCURSOR_PATH = "${config.home.homeDirectory}/.local/share/icons:/run/current-system/sw/share/icons";
  };

  programs.rofi.enable = true;

  programs.dux-files = {
    enable = true;
    systemd.enable = true;
    portal.enable = true;
  };

  home.packages = with pkgs; [
    bitwarden-desktop
    pipeweaver
    proton-cachyos_x86_64_v3
    qbittorrent
    vesktop
    wineWow64Packages.fonts
    (wineWow64Packages.waylandFull.override { wineRelease = "staging"; })
    yabridge
    yabridgectl
    (discord.override {
      withVencord = true;
    })
    inputs.prismlauncher.packages.${pkgs.stdenv.hostPlatform.system}.prismlauncher
    #inputs.serein.packages.${pkgs.stdenv.hostPlatform.system}.serein
    papirus-icon-theme
    (writeShellApplication {
      name = "screenshot-annotate";
      runtimeInputs = [
        coreutils
        grim
        slurp
        swappy
      ];
      text = ''
        if ! geometry=$(slurp); then
          exit 0
        fi

        screenshot=$(mktemp --suffix=.png)
        trap 'rm -f "$screenshot"' EXIT

        grim -g "$geometry" "$screenshot"

        mkdir -p "$HOME/Screenshots"
        swappy -f "$screenshot" \
          -o "$HOME/Screenshots/Screenshot-$(date +%Y-%m-%d-%H-%M-%S).png"
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
