{ config, pkgs, inputs, ... }:

{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  home.packages = [ pkgs.sops pkgs.age ];

  sops = {
    defaultSopsFile = ../secrets/github-token.yaml;
    # Backup: /mount/xali/.config/sops/age/keys.txt. Keep the local key for offline decryption.
    age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
    secrets.github-token = { };
  };
}
