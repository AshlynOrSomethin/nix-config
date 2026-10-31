{ config, pkgs, lib, inputs, ... }:

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
  imports = [
    ./hardware-configuration.nix
    ./fonts.nix
    ./home/flatpak.nix
    ./home/vscode.nix    
    ./uutils.nix
  ];

  nixpkgs.overlays = [ (final: prev: {
    inherit (prev.lixPackageSets.stable)
      nixpkgs-review
      nix-eval-jobs
      nix-fast-build
      colmena;
  }) ];

  nix.package = pkgs.lixPackageSets.stable.lix;

  security.sudo.enable = false;
  security.sudo-rs.enable = true;
  security.polkit.enablePkexecWrapper = true;

  boot.supportedFilesystems.zfs = lib.mkForce false;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
  }; 
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_cachyos-lto-znver4;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  fileSystems."/mount/xali" = {
    device = "ashlyn@xali.host:/home/ashlyn";
    fsType = "fuse.sshfs";
    options = [
      "_netdev"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "x-systemd.mount-timeout=30s"
      "IdentityFile=/home/ashlyn/.ssh/id_ed25519"
      "UserKnownHostsFile=/home/ashlyn/.ssh/known_hosts"
      "StrictHostKeyChecking=yes"
      "BatchMode=yes"
      "IdentitiesOnly=yes"
      "IdentityAgent=none"
      "ConnectTimeout=15"
      "ServerAliveInterval=15"
      "ServerAliveCountMax=3"
      "reconnect"
      "allow_other"
      "default_permissions"
      "uid=1000"
      "gid=100"
      "umask=077"
      "nodev"
      "nosuid"
      "noexec"
    ];
  };

  time.timeZone = "America/Chicago";

  i18n.defaultLocale = "en_US.UTF-8";

  services.displayManager.cosmic-greeter = {
    enable = true;
    package = inputs.cosmic-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      # The installer requires the daemon binary from the Cargo workspace.
      cargoBuildFlags = (old.cargoBuildFlags or []) ++ [ "--workspace" ];
    });
  };
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.cosmic-greeter.enableGnomeKeyring = true;
  services.udisks2.enable = true;

  programs.nix-ld.enable = true;
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  programs.qylock = {
    enable = true;
    theme = "pixel-night-city";
    quickshell.enable = false;
  };

  programs.niri.enable = true;
  programs.niri.package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
  programs.dank-material-shell = {
    enable = true;
    enableCalendarEvents = false;
    systemd.enable = true;
  };
  programs.dux-search.enable = true;
  programs.dux-search.systemd.enable = true;
  services.fprintd.enable = true;

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users."ashlyn" = {
    isNormalUser = true;
    description = "ashlyn";
    extraGroups = [ "networkmanager" "wheel" "vboxusers" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  nixpkgs.config.allowUnfree = true;

  virtualisation.virtualbox.host = {
    enable = true;
    enableKvm = true;
    addNetworkInterface = false;
    enableExtensionPack = true;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

  system.stateVersion = "26.05";
}
