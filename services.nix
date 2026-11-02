{ pkgs, inputs, ... }:

{
  services.displayManager.cosmic-greeter = {
    enable = true;
    package = inputs.cosmic-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      # The installer requires the daemon binary from the Cargo workspace.
      cargoBuildFlags = (old.cargoBuildFlags or []) ++ [ "--workspace" ];
    });
  };
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.cosmic-greeter.enableGnomeKeyring = true;
  security.polkit.enablePkexecWrapper = true;
  services.udisks2.enable = true;
  services.fprintd.enable = true;
  services.printing.enable = true;
  services.blueman.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
}
