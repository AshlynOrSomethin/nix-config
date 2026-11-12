{ lib, ... }:

let
  httpChecks = {
    Audiobookshelf = "http://127.0.0.1:13378/healthcheck";
    Authentik = "http://127.0.0.1:9180/-/health/ready/";
    Bitmagnet = "http://127.0.0.1:3333/";
    Chiyogami = "http://127.0.0.1:8000/";
    Forgejo = "http://127.0.0.1:3005/api/healthz";
    FreshRSS = "http://127.0.0.1:9900/";
    Grimmory = "http://127.0.0.1:6060/api/v1/healthcheck";
    iQbit = "http://127.0.0.1:8082/";
    "Pelican Panel" = "http://127.0.0.1:8080/";
    SearXNG = "http://127.0.0.1:8842/healthz";
  };
in
{
  services.postgresql = {
    ensureDatabases = [ "gatus" ];
    ensureUsers = [{
      name = "gatus";
      ensureDBOwnership = true;
    }];
  };
  services.postgresqlBackup.databases = [ "gatus" ];

  users.groups.gatus = { };
  users.users.gatus = {
    isSystemUser = true;
    group = "gatus";
  };
  services.gatus = {
    enable = true;
    settings = {
      web = {
        address = "127.0.0.1";
        port = 3001;
      };
      storage = {
        type = "postgres";
        path = "postgres://gatus@/gatus?host=/run/postgresql&sslmode=disable";
      };
      ui = {
        title = "Pulsar Uptime";
        header = "Pulsar Uptime";
        description = "Local application health checks";
      };
      endpoints = lib.mapAttrsToList (name: url: {
        inherit name url;
        group = "Applications";
        interval = "1m";
        client.timeout = "10s";
        conditions = [ "[STATUS] == 200" ];
      }) httpChecks ++ [{
        name = "SSH";
        group = "Infrastructure";
        url = "tcp://127.0.0.1:22";
        interval = "1m";
        conditions = [ "[CONNECTED] == true" ];
      }];
    };
  };
  systemd.services.gatus = {
    requires = [ "postgresql.target" "postgresql-setup.service" ];
    after = [ "postgresql.target" "postgresql-setup.service" ];
    serviceConfig.DynamicUser = lib.mkForce false;
  };

  services.nginx.virtualHosts."uptime.pulsar.ltd" = {
    forceSSL = true;
    sslCertificate = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
    sslCertificateKey = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
    locations."/".proxyPass = "http://127.0.0.1:3001";
  };
}
