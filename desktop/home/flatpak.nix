{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [ 
    flatpak-builder
    appstream
  ];

  services.flatpak = {
    enable = true;
    update.onActivation = true;

    packages = [
      "io.github.kolunmi.Bazaar"
      "com.github.tchx84.Flatseal"
      "org.kde.Sdk//6.10"
      "com.usebottles.bottles"
    ];
  };
}
