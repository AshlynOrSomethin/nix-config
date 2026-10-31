{ pkgs, inputs, ... }:

let
  gparted = pkgs.gparted.overrideAttrs (old: {
    preFixup = (old.preFixup or "") + ''
      gappsWrapperArgs+=(
        --set GTK_THEME Gruvbox-Dark
        --prefix XDG_DATA_DIRS : "${pkgs.gruvbox-gtk-theme}/share"
      )
    '';
  });
in
{
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    sshfs
    tealdeer
    bitwarden-cli
    cargo
    efibootmgr
    firefox
    fuzzel
    gh
    ghostty
    git
    gitoxide
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-ugly
    gst_all_1.gstreamer
    hyfetch
    inotify-tools
    inputs.fresh.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.jj.packages.${pkgs.stdenv.hostPlatform.system}.default
    jq
    ripgrep
    dust
    lazygit
    zoxide
    pay-respects
    xh
    systemctl-tui
    lazydocker
    direnv
    nix-direnv
    nh
    nvd
    comma
    nix-tree
    duf
    btop
    gping
    procs
    doggo
    atuin
    killall
    libargon2
    libinput
    libsecret
    lunar-client
    macchina
    nodejs
    grim
    pinentry-qt
    python3
    rustc
    qt6Packages.qt6ct
    gparted
    gruvbox-gtk-theme
    wget
    wl-clipboard
    xwayland-satellite
    lsd
  ];
}
