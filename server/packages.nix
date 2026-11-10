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
    fuzzel
    gh
    ghostty
    git
    gitoxide
    gping
    grim
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
    fastfetch
    nh
    nix-direnv
    nix-tree
    nodejs
    nvd
    pay-respects
    procs
    python3
    ripgrep
    rustc
    sequoia-chameleon-gnupg
    sequoia-sq
    sequoia-sqv
    sshfs
    systemctl-tui
    tealdeer
    valkey
    wget
    wl-clipboard
    xh
    xwayland-satellite
    yarn
    zoxide
  ];
}
