{ config, inputs, lib, pkgs, ... }:

let
  proxmoxPkgs = inputs.proxmox-nixos.inputs.nixpkgs-stable.legacyPackages.${config.nixpkgs.hostPlatform.system};
  pamModule = name: lib.mkForce "${proxmoxPkgs.pam}/lib/security/pam_${name}.so";
in
{
  imports = [ inputs.proxmox-nixos.nixosModules.proxmox-ve ];

  nixpkgs.overlays = [ inputs.proxmox-nixos.overlays.${config.nixpkgs.hostPlatform.system} ];

  services.proxmox-ve = {
    enable = true;
    ipAddress = "192.168.1.2";
    bridges = [ "vmbr0" ];
    package = pkgs.proxmox-ve.override {
      pve-manager = pkgs.pve-manager.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          substituteInPlace "$out/${proxmoxPkgs.perl.libPrefix}/${proxmoxPkgs.perl.version}/PVE/API2/Nodes.pm" --replace-fail \
            "['login'" "['${lib.getBin pkgs.util-linux}/bin/login'"
        '';
      });
    };
  };

  # Proxmox's stable runtime cannot load PAM modules built against the host's newer glibc.
  security.pam.services.proxmox-ve-auth = {
    fprintAuth = false;
    rules = {
      account.unix.modulePath = pamModule "unix";
      auth = {
        faillock.modulePath = pamModule "faillock";
        unix.modulePath = pamModule "unix";
        deny.modulePath = pamModule "deny";
      };
      password.unix.modulePath = pamModule "unix";
      session = {
        env.modulePath = pamModule "env";
        unix.modulePath = pamModule "unix";
        limits.modulePath = pamModule "limits";
      };
    };
  };

  systemd.services.proxmox-admin = {
    description = "Configure the Proxmox administrator account";
    wantedBy = [ "multi-user.target" ];
    requires = [ "pve-cluster.service" ];
    after = [ "pve-cluster.service" ];
    path = [ config.services.proxmox-ve.package pkgs.jq ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      users=$(pveum user list --output-format json)
      existing=$(printf '%s' "$users" | jq -r '.[] | select(.userid == "ashlyn@pam") | .userid')
      if [ -z "$existing" ]; then
        pveum user add ashlyn@pam --enable 1
      else
        pveum user modify ashlyn@pam --enable 1
      fi
      pveum acl modify / --users ashlyn@pam --roles Administrator --propagate 1
    '';
  };

  nix.settings = {
    extra-substituters = [ "https://cache.saumon.network/proxmox-nixos" ];
    extra-trusted-public-keys = [
      "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM="
    ];
  };
}
