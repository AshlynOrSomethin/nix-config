{ config, lib, pkgs, ... }:

let
  migration = pkgs.writeShellApplication {
    name = "luckperms-migrate";
    runtimeInputs = [
      pkgs.coreutils pkgs.curl config.virtualisation.docker.package pkgs.mariadb
      pkgs.mariadb.client pkgs.nix pkgs.postgresql_16 pkgs.python3 pkgs.systemd pkgs.util-linux
    ];
    text = ''
      exec python3 ${./native-migration}/luckperms.py "$@"
    '';
  };
  servers = pkgs.writeShellApplication {
    name = "luckperms-servers";
    runtimeInputs = [
      pkgs.coreutils config.virtualisation.docker.package pkgs.jdk21
      pkgs.postgresql_16 pkgs.python3 pkgs.systemd pkgs.util-linux
    ];
    text = ''
      exec python3 ${./native-migration}/luckperms-servers.py "$@"
    '';
  };
in
{
  environment.systemPackages = [ migration servers ];
  services.postgresql = {
    ensureDatabases = [ "s14_minecraft" ];
    ensureUsers = [{
      name = "s14_minecraft";
      ensureDBOwnership = true;
    }];
    authentication = lib.mkBefore ''
      local s14_minecraft s14_minecraft scram-sha-256
    '';
  };
  services.postgresqlBackup.databases = [ "s14_minecraft" ];

  systemd.sockets.luckperms-postgresql = {
    description = "PostgreSQL access on the Pelican bridge only";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "172.18.0.1:5432";
      BindToDevice = "pelican0";
      NoDelay = true;
    };
  };
  systemd.services.luckperms-postgresql = {
    description = "Forward Pelican PostgreSQL connections to the native Unix socket";
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd /run/postgresql/.s.PGSQL.5432";
      DynamicUser = true;
      PrivateTmp = true;
      ProtectHome = true;
    };
  };
}
