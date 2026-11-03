{ config, lib, pkgs, ... }:

let
  backupDir = "${config.users.users.ashlyn.home}/Vaultwarden backups";
  sshOptions = [
    "-o" "BatchMode=yes"
    "-o" "StrictHostKeyChecking=yes"
    "-o" "UserKnownHostsFile=${config.users.users.ashlyn.home}/.ssh/known_hosts"
    "-o" "IdentitiesOnly=yes"
    "-o" "IdentityAgent=none"
    "-o" "ConnectTimeout=15"
    "-o" "ServerAliveInterval=15"
    "-o" "ServerAliveCountMax=3"
    "-i" "${config.users.users.ashlyn.home}/.ssh/id_ed25519"
  ];
  sshArgs = lib.escapeShellArgs sshOptions;
  setup = pkgs.writeShellApplication {
    name = "vaultwarden-backup-setup";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      ssh ${sshArgs} ashlyn@xali.host \
        'mkdir -p ~/.cache/vaultwarden-backup-setup && chmod 700 ~/.cache/vaultwarden-backup-setup'
      scp ${sshArgs} \
        ${./home/vaultwarden-backup-setup.sh} \
        ashlyn@xali.host:.cache/vaultwarden-backup-setup/setup.sh
      scp ${sshArgs} \
        ${./home/vaultwarden-backup-export.sh} \
        ashlyn@xali.host:.cache/vaultwarden-backup-setup/export.sh
      ssh -t ${sshArgs} ashlyn@xali.host \
        'sudo bash ~/.cache/vaultwarden-backup-setup/setup.sh'
    '';
  };
  backup = pkgs.writeShellApplication {
    name = "vaultwarden-backup";
    runtimeInputs = [ pkgs.openssh pkgs.coreutils pkgs.findutils pkgs.gnutar pkgs.gzip ];
    text = ''
      umask 077
      destination=${lib.escapeShellArg backupDir}
      mkdir -p "$destination"
      chown root:root "$destination"
      chmod 0700 "$destination"
      partial=$(mktemp "$destination/.vaultwarden-XXXXXXXX.partial")
      trap 'rm -f -- "$partial"' EXIT
      ssh ${sshArgs} ashlyn@xali.host \
        'sudo -n /usr/local/sbin/vaultwarden-backup-export' > "$partial"
      tar -tzf "$partial" >/dev/null
      name="vaultwarden-$(date -u +%Y%m%dT%H%M%S)-$(basename "$partial" .partial).tar.gz"
      mv -- "$partial" "$destination/$name"
      find "$destination" -maxdepth 1 -type f -name 'vaultwarden-*.tar.gz' -mmin +43200 -delete
      printf 'Saved backup: %s\n' "$destination/$name"
    '';
  };
in
{
  environment.systemPackages = [ setup backup ];

  systemd.services.vaultwarden-backup = {
    description = "Back up Vaultwarden from xali.host over SSH";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      User = "root";
      Group = "root";
      Type = "oneshot";
      ExecStart = lib.getExe backup;
      UMask = "0077";
      TimeoutStartSec = "2h";
    };
  };

  systemd.timers.vaultwarden-backup = {
    description = "Back up Vaultwarden every 12 hours";
    timerConfig = {
      OnCalendar = "*-*-* 00,12:00:00";
      Persistent = true;
      RandomizedDelaySec = "5min";
    };
    wantedBy = [ "timers.target" ];
  };
}
