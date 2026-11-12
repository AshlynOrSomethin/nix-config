{ config, lib, pkgs, ... }:

let
  puressh = pkgs.callPackage ../packages/puressh.nix { };
in
{
  programs.ssh.package = puressh;
  environment.systemPackages = [ (lib.hiPrio puressh) ];

  # Retain NixOS's OpenSSH module for key provisioning, PAM and configuration.
  services.openssh.package = pkgs.openssh;
  system.checks = lib.optionals config.services.openssh.enable [
    (pkgs.runCommand "check-puressh-config" { } ''
      ${puressh}/bin/sshd -G -T -C lport=22 -f ${config.environment.etc."ssh/sshd_config".source} > /dev/null
      touch "$out"
    '')
  ];
  systemd.services.sshd = lib.mkIf config.services.openssh.enable {
    environment.LD_LIBRARY_PATH = lib.mkForce "${lib.makeLibraryPath [ pkgs.pam ]}:${config.system.nssModules.path}";
    serviceConfig = {
      Type = lib.mkForce "notify";
      ExecStart = lib.mkForce "${puressh}/bin/sshd -D -f /etc/ssh/sshd_config";
      ExecStartPre = "${puressh}/bin/sshd -t -f /etc/ssh/sshd_config";
    };
  };
}
