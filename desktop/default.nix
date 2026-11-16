{ config, lib, ... }:

{
  imports = [
    ../shared
    ../shared/puressh.nix
    ./hardware-configuration.nix
    ./boot.nix
    ./services.nix
    ./packages.nix
    ./prores.nix
    ./home/gaming.nix
    ./shells.nix
    ./virtualization.nix
    ./fonts.nix
    ./davinci.nix
    ./home/flatpak.nix
    ./home/vscode.nix
  ];

  # uutils mv otherwise prompts before replacing symlinks to read-only store paths.
  system.activationScripts.binsh = lib.mkForce (lib.stringAfter [ "stdio" ] ''
    mkdir -p /bin
    chmod 0755 /bin
    ln -sfn ${lib.escapeShellArg config.environment.binsh} /bin/.sh.tmp
    mv -f /bin/.sh.tmp /bin/sh
  '');

  system.activationScripts.usrbinenv = lib.mkForce (
    if config.environment.usrbinenv != null then ''
      mkdir -p /usr/bin
      chmod 0755 /usr/bin
      ln -sfn ${lib.escapeShellArg config.environment.usrbinenv} /usr/bin/.env.tmp
      mv -f /usr/bin/.env.tmp /usr/bin/env
    '' else ''
      rm -f /usr/bin/env
    ''
  );
}
