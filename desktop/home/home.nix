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

  wineVersionLine = lib.removeSuffix "\n" (builtins.readFile "${inputs.wine-cachyos}/VERSION");
  wineVersion =
    if lib.hasPrefix "Wine version " wineVersionLine then
      lib.removePrefix "Wine version " wineVersionLine
    else
      throw "Could not determine the CachyOS Wine version";
  wineCachyos = { x11Support, waylandSupport }:
    (pkgs.wineWow64Packages.full.override { inherit x11Support waylandSupport; }).overrideAttrs (old:
      {
        pname = "wine-cachyos";
        version = "${wineVersion}-cachyos-${inputs.wine-cachyos.shortRev}";
        src = inputs.wine-cachyos;
        # CachyOS changes the context expected by nixpkgs' certificate patch.
        patches = lib.filter
          (patch: builtins.baseNameOf (toString patch) != "cert-path.patch")
          old.patches;
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.autoconf pkgs.perl pkgs.python3 ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace dlls/crypt32/unixlib.c \
            --replace-fail \
            'if ((additional_dir = getenv( "WINE_ADDITIONAL_CERTS_DIR" )))' \
            'if ((additional_dir = getenv( "NIX_SSL_CERT_FILE" )))
              import_certs_from_path( additional_dir, TRUE );

          if ((additional_dir = getenv( "WINE_ADDITIONAL_CERTS_DIR" )))'
        '';
        preConfigure = (old.preConfigure or "") + ''
          patchShebangs autogen.sh tools/make_requests tools/make_specfiles dlls/winevulkan/make_vulkan
          XDG_CACHE_HOME="$TMPDIR" ./autogen.sh
        '';
        postInstall = (old.postInstall or "") + ''
          # CachyOS's Proton loader expects 64-bit binaries in i386-unix.
          if grep -Fq 'i386-unix/wine64-preloader' dlls/ntdll/unix/loader.c; then
            mkdir -p "$out/lib/wine/i386-unix"
            for loader in wine64 wine64-preloader; do
              if [ ! -x "$out/lib/wine/x86_64-unix/$loader" ]; then
                echo "CachyOS Wine loader $loader is missing" >&2
                exit 1
              fi
              ln -s "../x86_64-unix/$loader" "$out/lib/wine/i386-unix/$loader"
            done
          fi
        '';
      }
      // lib.optionalAttrs (!waylandSupport) {
        configureFlags = old.configureFlags ++ [ "--without-wayland" ];
      });
  wineWayland = wineCachyos { x11Support = false; waylandSupport = true; };

  # Yabridge embeds plugin editors through XWayland.
  wineForYabridge = wineCachyos { x11Support = true; waylandSupport = false; };
  yabridgeWinePackages = pkgs.wineWow64Packages // { yabridge = wineForYabridge; };
  yabridge = pkgs.yabridge.override { wineWow64Packages = yabridgeWinePackages; };
  yabridgectl = pkgs.yabridgectl.override {
    inherit yabridge;
    wineWow64Packages = yabridgeWinePackages;
  };
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
    wineWayland
    wineWow64Packages.fonts
    yabridge
    yabridgectl
    # Wine's display driver is shared by processes using the same prefix.
    (writeShellScriptBin "wine-yabridge" ''
      export WINEPREFIX="''${WINEPREFIX:-$HOME/.wine-yabridge}"
      exec ${wineForYabridge}/bin/wine "$@"
    '')
    (discord.override {
      withVencord = true;
    })
    inputs.prismlauncher.packages.${pkgs.stdenv.hostPlatform.system}.prismlauncher
    inputs.serein.packages.${pkgs.stdenv.hostPlatform.system}.serein
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
