{ pkgs, lib, ... }:
let
  segoe-ui-emoji = pkgs.runCommand "segoe-ui-emoji" { } ''
    install -Dm444 ${./fonts/seguiemj.ttf} $out/share/fonts/truetype/seguiemj.ttf
  '';
in
{
  # corefonts and vista-fonts are unfree
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "corefonts"
      "vista-fonts"
    ];

  fonts.packages = with pkgs; [
    # Noto / general
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf

    # Coding / terminal
    fira-code
    fira-code-symbols
    powerline-fonts
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    terminus_font

    # Microsoft fonts
    corefonts    # Andale Mono, Arial, Arial Black, Comic Sans MS, Courier New,
                 # Georgia, Impact, Times New Roman, Trebuchet MS, Verdana, Webdings
    vista-fonts  # Calibri, Cambria, Candara, Consolas, Constantia, Corbel

    # Local font
    segoe-ui-emoji
  ] ++ builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

  # Prefer Segoe UI Emoji, fall back to Noto
  fonts.fontconfig.defaultFonts.emoji = [ "Segoe UI Emoji" "Noto Color Emoji" ];
}
