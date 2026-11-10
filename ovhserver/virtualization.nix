{ pkgs, ... }:

{
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.docker.enable = true;

  environment.systemPackages = [ pkgs.distrobox ];
}
