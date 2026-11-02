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

  # Custom python environment with pygobject3 included globally
  myPython = pkgs.python3.withPackages (ps: [
    ps.pygobject3
  ]);
in
{
  environment.systemPackages = with pkgs; [
    atuin
    bitwarden-cli
    btop
    cargo
    comma
    direnv
    doggo
    duf
    dust
    efibootmgr
    ffmpeg
    firefox
    fuzzel
    gh
    ghostty
    git
    gitoxide
    gparted
    gping
    grim
    gruvbox-gtk-theme
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
    killall
    lazydocker
    lazygit
    libargon2
    libinput
    libsecret
    lsd
    lunar-client
    macchina
    nh
    nix-direnv
    nix-tree
    nodejs
    nvd
    overskride
    pay-respects
    pinentry-qt
    procs
    myPython                    # Replaces plain python3 and pygobject3
    qt6Packages.qt6ct
    ripgrep
    rustc
    sequoia-chameleon-gnupg
    sequoia-sq
    sequoia-sqv
    sshfs
    systemctl-tui
    tealdeer
    wget
    wl-clipboard
    xh
    xwayland-satellite
    zoxide
  ];
}
