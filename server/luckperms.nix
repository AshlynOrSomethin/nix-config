{ config, lib, pkgs, ... }:

{
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

  systemd.sockets.luckperms-podman-postgresql = {
    description = "PostgreSQL access on the Wings Podman bridge";
    wantedBy = [ "sockets.target" ];
    requires = [ "podman-pelican-network.service" ];
    after = [ "podman-pelican-network.service" ];
    socketConfig = {
      ListenStream = "10.245.0.1:5432";
      BindToDevice = "pelican-pod0";
      NoDelay = true;
    };
  };
  systemd.services.luckperms-podman-postgresql = {
    description = "Forward Wings Podman PostgreSQL connections to the native Unix socket";
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
