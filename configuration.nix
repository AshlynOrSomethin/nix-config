{ config, pkgs, inputs, ... }:

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

  environment.etc."gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Gruvbox-Dark
    gtk-application-prefer-dark-theme=true
  '';

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
  }; 
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_cachyos-lto-znver4;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

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
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
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
    #pinentry-qt
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
