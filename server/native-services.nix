{ config, lib, pkgs, ... }:

let
  ready = "/var/lib/native-services-migration/ready";
  guarded = oldUnits: {
    unitConfig.ConditionPathExists = ready;
    conflicts = oldUnits;
    after = oldUnits;
  };
  postgresClient = {
    unitConfig.ConditionPathExists = ready;
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
  };
  migrate = pkgs.writeShellApplication {
    name = "native-services-migrate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      config.virtualisation.docker.package
      pkgs.mariadb.client
      pkgs.nix
      pkgs.openssh
      pkgs.postgresql_16
      (pkgs.python3.withPackages (ps: [ ps.pglast ]))
      pkgs.rsync
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      exec python3 ${./native-migration/migrate.py} "$@"
    '';
  };
  sharedMigrate = pkgs.writeShellApplication {
    name = "shared-mariadb-migrate";
    runtimeInputs = [
      pkgs.coreutils pkgs.curl config.virtualisation.docker.package pkgs.mariadb.client
      pkgs.nix pkgs.pgloader pkgs.php pkgs.postgresql_16 pkgs.python3 pkgs.rsync
      pkgs.systemd pkgs.util-linux
    ];
    text = ''
      exec python3 ${./native-migration}/shared-mariadb.py "$@"
    '';
  };
in
{
  environment.systemPackages = [ migrate sharedMigrate ];

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    dataDir = "/var/lib/postgresql/16";
    enableTCPIP = false;
    initdbArgs = [ "--locale=en_US.UTF-8" ];
    settings = {
      listen_addresses = lib.mkForce "";
      max_connections = 250;
      timezone = "UTC";
      log_timezone = "UTC";
    };
    ensureDatabases = [ "authentik" "bitmagnet" "forgejo" "freshrss" "pelican" ];
    ensureUsers = map (name: {
      inherit name;
      ensureDBOwnership = true;
    }) [ "authentik" "bitmagnet" "forgejo" "freshrss" ] ++ [
      { name = "pelican-panel"; }
    ];
    authentication = lib.mkBefore ''
      local authentik authentik scram-sha-256
      local bitmagnet bitmagnet scram-sha-256
      local freshrss freshrss scram-sha-256
    '';
  };

  services.postgresqlBackup = {
    enable = true;
    databases = [ "authentik" "bitmagnet" "forgejo" "freshrss" "pelican" ];
    compression = "zstd";
  };
  # Keep the directory inode stable for containers binding the Unix socket directory.
  systemd.services.postgresql.serviceConfig.RuntimeDirectoryPreserve = "yes";

  services.audiobookshelf = {
    enable = true;
    port = 13378;
    host = "0.0.0.0";
  };
  users.users.audiobookshelf.extraGroups = [ "users" ];
  systemd.services.audiobookshelf = lib.mkMerge [
    (guarded [ "docker-audiobookshelf-audiobookshelf-1.service" ])
    {
      unitConfig.RequiresMountsFor = [ "/media/sda" "/Books/AudioBooks" "/Podcasts" ];
      environment = {
        CONFIG_PATH = "/var/lib/audiobookshelf/config";
        METADATA_PATH = "/var/lib/audiobookshelf/metadata";
        TZ = "America/Chicago";
      };
      serviceConfig.BindPaths = [
        "/var/lib/audiobookshelf/config:/config"
        "/var/lib/audiobookshelf/metadata:/metadata"
        "/Books/AudioBooks:/audiobooks"
        "/Podcasts:/podcasts"
      ];
    }
  ];

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
    # Keep the complete imported configuration, including SMTP and signing secrets.
    useWizard = true;
    secrets = lib.mkForce { };
    customDir = "/var/lib/forgejo/gitea";
    repositoryRoot = "/var/lib/forgejo/git/repositories";
    database = {
      type = "postgres";
      socket = "/run/postgresql";
    };
    lfs = {
      enable = true;
      contentDir = "/var/lib/forgejo/git/lfs";
    };
    settings.server.START_SSH_SERVER = true;
  };
  systemd.services.forgejo = lib.mkMerge [
    (guarded [ "docker-forgejo.service" ])
    {
      environment = {
        FORGEJO_WORK_DIR = lib.mkForce "/data/gitea";
        HOME = lib.mkForce "/data/git";
      };
      serviceConfig = {
        BindPaths = [ "/var/lib/forgejo:/data" ];
        # The retained SSH port 222 requires a capability in the host user namespace.
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = lib.mkForce [ "CAP_NET_BIND_SERVICE" ];
        PrivateUsers = lib.mkForce false;
      };
    }
  ];

  services.searx = {
    enable = true;
    configureUwsgi = true;
    environmentFile = "/var/lib/native-services-migration/searx.env";
    redisCreateLocally = true;
    settings = {
      general.instance_name = "Pulse Search";
      server = {
        secret_key = "$SEARX_SECRET_KEY";
        base_url = "https://search.pulsar.ltd/";
        limiter = true;
        image_proxy = true;
      };
    };
    limiterSettings.botdetection.trusted_proxies = [ "127.0.0.1" "::1" ];
    uwsgiConfig = {
      http = "0.0.0.0:8842";
      disable-logging = true;
      workers = 2;
      threads = 2;
    };
  };
  systemd.services.uwsgi = guarded [ "docker-searxng.service" ];

  systemd.services.docker-authentik-server-1 = postgresClient;
  systemd.services.docker-authentik-worker-1 = postgresClient;
  systemd.services.docker-bitmagnet = postgresClient;
  systemd.services.postgresqlBackup-authentik.unitConfig.ConditionPathExists = ready;
  systemd.services.postgresqlBackup-bitmagnet.unitConfig.ConditionPathExists = ready;
  systemd.services.postgresqlBackup-forgejo.unitConfig.ConditionPathExists = ready;
  systemd.services.postgresqlBackup-freshrss.unitConfig.ConditionPathExists =
    "/var/lib/shared-mariadb-migration/ready";
  systemd.services.postgresqlBackup-pelican.unitConfig.ConditionPathExists =
    "/var/lib/shared-mariadb-migration/ready";
  systemd.services.docker-freshrss = {
    unitConfig.ConditionPathExists = "/var/lib/shared-mariadb-migration/ready";
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
  };
}
