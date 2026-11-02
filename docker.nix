{ config, lib, pkgs, ... }:

# Systemd replaces Compose as the container supervisor. Keep the runtime
# environment files in /var/lib/docker-compose-env backed up separately.
let
  docker = "${config.virtualisation.docker.package}/bin/docker";
  containerNames = [ "audiobookshelf-audiobookshelf-1" "forgejo" "searxng" "uptimekuma-uptime-kuma-1" "authentik-postgresql-1" "authentik-server-1" "authentik-worker-1" "bazarr" "bitmagnet" "bitmagnet-postgres" "chiyogami" "freshrss" "grimmory" "grimmory-mariadb-1" "iqbit" "prowlarr" "radarr" "sonarr" ];
  healthyContainers = [ "authentik-postgresql-1" "bitmagnet-postgres" "grimmory-mariadb-1" ];
  networks = {
    "audiobookshelf_default" = "bridge";
    "forgejo_forgejo" = "bridge";
    "searxng_default" = "bridge";
    "uptimekuma_default" = "bridge";
    "authentik_default" = "bridge";
    "bazarr_default" = "bridge";
    "bitmagnet_default" = "bridge";
    "chiyogami_default" = "bridge";
    "freshrss_default" = "bridge";
    "grimmory_default" = "bridge";
    "iqbit_default" = "bridge";
    "prowlarr_default" = "bridge";
    "radarr_default" = "bridge";
    "sonarr_default" = "bridge";
  };
  volumes = {
    "authentik_database" = "local";
    "freshrss_data" = "local";
    "freshrss_extensions" = "local";
  };
  bindPaths = {
    "audiobookshelf-audiobookshelf-1" = [ "/etc/docker-compose/AudioBookShelf/audiobookshelf/config" "/etc/docker-compose/AudioBookShelf/audiobookshelf/metadata" "/Books/AudioBooks" "/Podcasts" ];
    "forgejo" = [ "/etc/docker-compose/ForgeJo/forgejo" "/etc/localtime" ];
    "searxng" = [ "/var/www/SearXNG/config" "/var/www/SearXNG/data" ];
    "uptimekuma-uptime-kuma-1" = [ "/etc/docker-compose/UptimeKuma/data" ];
    "authentik-server-1" = [ "/etc/docker-compose/authentik/data" "/etc/docker-compose/authentik/custom-templates" ];
    "authentik-worker-1" = [ "/var/run/docker.sock" "/etc/docker-compose/authentik/data" "/etc/docker-compose/authentik/certs" "/etc/docker-compose/authentik/custom-templates" ];
    "bazarr" = [ "/var/www/bazarr/config" "/Movies" "/TV" ];
    "bitmagnet-postgres" = [ "/etc/docker-compose/bitmagnet/bitmagnet/postgres" ];
    "chiyogami" = [ "/etc/docker-compose/chiyogami/pastes" ];
    "freshrss" = [ "/var/www/FreshRSS" ];
    "grimmory" = [ "/etc/docker-compose/grimmory/data" "/Books" "/etc/docker-compose/grimmory/bookdrop" ];
    "grimmory-mariadb-1" = [ "/etc/docker-compose/grimmory/mariadb/config" ];
    "iqbit" = [ "/etc/docker-compose/iQbit/server.js" ];
    "prowlarr" = [ "/var/www/Prowlarr/data" ];
    "radarr" = [ "/var/www/radarr/data" "/Movies" "/media/md/Downloads" ];
    "sonarr" = [ "/var/www/sonarr/data" "/TV" "/media/md/Downloads" ];
  };
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      mariadb = {
        image = "mariadb:13.0";
        autoStart = true;
        ports = [ "3306:3306" ];
        volumes = [ "/var/lib/mariadb:/var/lib/mysql" ];
      };

      # Secret values live in root-only environment files, never in the Nix store.
      "audiobookshelf-audiobookshelf-1" = {
        image = "ghcr.io/advplyr/audiobookshelf:latest";
        autoStart = true;
        environment = {
          "TZ" = "America/Chicago";
        };
        ports = [ "13378:80" ];
        volumes = [ "/etc/docker-compose/AudioBookShelf/audiobookshelf/config:/config" "/etc/docker-compose/AudioBookShelf/audiobookshelf/metadata:/metadata" "/Books/AudioBooks:/audiobooks" "/Podcasts:/podcasts" ];
        networks = [ "audiobookshelf_default" ];
        extraOptions = [ "--network-alias=audiobookshelf" ];
      };

      "forgejo" = {
        image = "codeberg.org/forgejo/forgejo:17";
        autoStart = true;
        environment = {
          "USER_GID" = "1000";
          "USER_UID" = "1000";
        };
        ports = [ "3005:3000" "222:22" ];
        volumes = [ "/etc/docker-compose/ForgeJo/forgejo:/data" "/etc/localtime:/etc/localtime:ro" ];
        networks = [ "forgejo_forgejo" ];
        extraOptions = [ "--network-alias=server" ];
      };

      "searxng" = {
        image = "ghcr.io/privau/searxng:latest";
        autoStart = true;
        environment = {
          "CONTACT" = "mailto:ashlyn@pulsar.ltd";
          "NAME" = "Pulse Search";
        };
        ports = [ "8842:8080" ];
        volumes = [ "/var/www/SearXNG/config:/etc/searxng" "/var/www/SearXNG/data:/var/cache/searxng" ];
        networks = [ "searxng_default" ];
        extraOptions = [ "--network-alias=searxng" ];
      };

      "uptimekuma-uptime-kuma-1" = {
        image = "louislam/uptime-kuma:2";
        autoStart = true;
        ports = [ "3001:3001" ];
        volumes = [ "/etc/docker-compose/UptimeKuma/data:/app/data" ];
        networks = [ "uptimekuma_default" ];
        extraOptions = [ "--network-alias=uptime-kuma" ];
      };

      "authentik-postgresql-1" = {
        image = "docker.io/library/postgres:16-alpine";
        autoStart = true;
        environment = {
          "COMPOSE_PORT_HTTP" = "9180";
          "COMPOSE_PORT_HTTPS" = "9143";
          "POSTGRES_DB" = "authentik";
          "POSTGRES_USER" = "authentik";
        };
        environmentFiles = [ "/var/lib/docker-compose-env/authentik-postgresql-1.env" ];
        volumes = [ "authentik_database:/var/lib/postgresql/data" ];
        networks = [ "authentik_default" ];
        extraOptions = [ "--network-alias=postgresql" "--health-cmd=pg_isready -d \${POSTGRES_DB} -U \${POSTGRES_USER}" "--health-interval=30s" "--health-timeout=5s" "--health-start-period=20s" "--health-retries=5" ];
      };

      "authentik-server-1" = {
        image = "ghcr.io/goauthentik/server:2026.8.3";
        autoStart = true;
        environment = {
          "AUTHENTIK_POSTGRESQL__HOST" = "postgresql";
          "AUTHENTIK_POSTGRESQL__NAME" = "authentik";
          "AUTHENTIK_POSTGRESQL__USER" = "authentik";
          "COMPOSE_PORT_HTTP" = "9180";
          "COMPOSE_PORT_HTTPS" = "9143";
        };
        environmentFiles = [ "/var/lib/docker-compose-env/authentik-server-1.env" ];
        ports = [ "9180:9000" "9143:9443" ];
        volumes = [ "/etc/docker-compose/authentik/data:/data" "/etc/docker-compose/authentik/custom-templates:/templates" ];
        networks = [ "authentik_default" ];
        dependsOn = [ "authentik-postgresql-1" ];
        cmd = [ "server" ];
        extraOptions = [ "--network-alias=server" "--shm-size=536870912" ];
      };

      "authentik-worker-1" = {
        image = "ghcr.io/goauthentik/server:2026.8.3";
        autoStart = true;
        environment = {
          "AUTHENTIK_POSTGRESQL__HOST" = "postgresql";
          "AUTHENTIK_POSTGRESQL__NAME" = "authentik";
          "AUTHENTIK_POSTGRESQL__USER" = "authentik";
          "COMPOSE_PORT_HTTP" = "9180";
          "COMPOSE_PORT_HTTPS" = "9143";
        };
        environmentFiles = [ "/var/lib/docker-compose-env/authentik-worker-1.env" ];
        volumes = [ "/var/run/docker.sock:/var/run/docker.sock" "/etc/docker-compose/authentik/data:/data" "/etc/docker-compose/authentik/certs:/certs" "/etc/docker-compose/authentik/custom-templates:/templates" ];
        networks = [ "authentik_default" ];
        dependsOn = [ "authentik-postgresql-1" ];
        cmd = [ "worker" ];
        user = "root";
        extraOptions = [ "--network-alias=worker" "--shm-size=536870912" ];
      };

      "bazarr" = {
        image = "lscr.io/linuxserver/bazarr:latest";
        autoStart = true;
        environment = {
          "PGID" = "1000";
          "PUID" = "1000";
          "TZ" = "America/Chicago";
        };
        ports = [ "6767:6767" ];
        volumes = [ "/var/www/bazarr/config:/config" "/Movies:/movies" "/TV:/tv" ];
        networks = [ "bazarr_default" ];
        extraOptions = [ "--network-alias=bazarr" ];
      };

      "bitmagnet" = {
        # The old /etc/bitmagnet config is unavailable; use image defaults.
        image = "ghcr.io/bitmagnet-io/bitmagnet:latest";
        autoStart = true;
        environment = {
          "POSTGRES_HOST" = "postgres";
        };
        environmentFiles = [ "/var/lib/docker-compose-env/bitmagnet.env" ];
        ports = [ "3333:3333" "3334:3334" "3334:3334/udp" ];
        networks = [ "bitmagnet_default" ];
        dependsOn = [ "bitmagnet-postgres" ];
        cmd = [ "worker" "run" "--keys=http_server" "--keys=queue_server" "--keys=dht_crawler" ];
        extraOptions = [ "--network-alias=bitmagnet" ];
      };

      "bitmagnet-postgres" = {
        image = "postgres:16-alpine";
        autoStart = true;
        environment = {
          "PGUSER" = "postgres";
          "POSTGRES_DB" = "bitmagnet";
        };
        environmentFiles = [ "/var/lib/docker-compose-env/bitmagnet-postgres.env" ];
        volumes = [ "/etc/docker-compose/bitmagnet/bitmagnet/postgres:/var/lib/postgresql/data:Z" ];
        networks = [ "bitmagnet_default" ];
        extraOptions = [ "--network-alias=postgres" "--shm-size=1073741824" "--health-cmd=pg_isready -U postgres" "--health-interval=10s" "--health-start-period=2m0s" ];
      };

      "chiyogami" = {
        image = "ghcr.io/rhee876527/chiyogami";
        autoStart = true;
        environmentFiles = [ "/var/lib/docker-compose-env/chiyogami.env" ];
        ports = [ "8000:8000" ];
        volumes = [ "/etc/docker-compose/chiyogami/pastes:/pastes" ];
        networks = [ "chiyogami_default" ];
        extraOptions = [ "--network-alias=chiyogami" "--cap-add=SETGID" "--cap-add=SETUID" "--cap-add=CHOWN" "--cap-drop=ALL" "--security-opt=no-new-privileges" ];
      };

      "freshrss" = {
        image = "lscr.io/linuxserver/freshrss:latest";
        autoStart = true;
        environment = {
          "PGID" = "1000";
          "PUID" = "1000";
          "TZ" = "America/Chicago";
        };
        ports = [ "9900:80" ];
        volumes = [ "/var/www/FreshRSS:/config" "freshrss_data:/var/www/FreshRSS/data" "freshrss_extensions:/var/www/FreshRSS/extensions" ];
        networks = [ "freshrss_default" ];
        extraOptions = [ "--network-alias=freshrss" "--add-host=host.docker.internal=host-gateway" ];
      };

      "grimmory" = {
        image = "ghcr.io/grimmory-tools/grimmory";
        autoStart = true;
        environment = {
          "API_DOCS_ENABLED" = "false";
          "DATABASE_USERNAME" = "grimmory";
          "DISK_TYPE" = "LOCAL";
          "GROUP_ID" = "1000";
          "TZ" = "America/Chicago";
          "USER_ID" = "1000";
        };
        environmentFiles = [ "/var/lib/docker-compose-env/grimmory.env" ];
        ports = [ "6060:6060" ];
        volumes = [ "/etc/docker-compose/grimmory/data:/app/data" "/Books:/books" "/etc/docker-compose/grimmory/bookdrop:/bookdrop" ];
        networks = [ "grimmory_default" ];
        dependsOn = [ "grimmory-mariadb-1" ];
        extraOptions = [ "--network-alias=grimmory" "--health-cmd=wget -q -O - http://localhost:6060/api/v1/healthcheck" "--health-interval=1m0s" "--health-timeout=10s" "--health-start-period=1m0s" "--health-retries=5" ];
      };

      "grimmory-mariadb-1" = {
        image = "lscr.io/linuxserver/mariadb:11.4.5";
        autoStart = true;
        environment = {
          "MYSQL_DATABASE" = "grimmory";
          "MYSQL_USER" = "grimmory";
          "PGID" = "1000";
          "PUID" = "1000";
          "TZ" = "America/Chicago";
        };
        environmentFiles = [ "/var/lib/docker-compose-env/grimmory-mariadb-1.env" ];
        volumes = [ "/etc/docker-compose/grimmory/mariadb/config:/config" ];
        networks = [ "grimmory_default" ];
        extraOptions = [ "--network-alias=mariadb" "--health-cmd=mariadb-admin ping -h localhost" "--health-interval=5s" "--health-timeout=5s" "--health-retries=10" ];
      };

      "iqbit" = {
        image = "ghcr.io/ashlynorsomethin/iqbit:latest";
        autoStart = true;
        environment = {
          "QBIT_HOST" = "http://pulsar.ltd:8080";
        };
        ports = [ "8082:8081" ];
        volumes = [ "/etc/docker-compose/iQbit/server.js:/usr/src/node-app/server/server.js:ro,Z" ];
        networks = [ "iqbit_default" ];
        extraOptions = [ "--network-alias=iqbit" ];
      };

      "prowlarr" = {
        image = "lscr.io/linuxserver/prowlarr:latest";
        autoStart = true;
        environment = {
          "PGID" = "1000";
          "PUID" = "1000";
          "TZ" = "America/Chicago";
        };
        ports = [ "9696:9696" ];
        volumes = [ "/var/www/Prowlarr/data:/config" ];
        networks = [ "prowlarr_default" ];
        extraOptions = [ "--network-alias=prowlarr" ];
      };

      "radarr" = {
        image = "lscr.io/linuxserver/radarr:latest";
        autoStart = true;
        environment = {
          "PGID" = "1000";
          "PUID" = "1000";
          "TZ" = "America/Chicago";
        };
        ports = [ "7878:7878" ];
        volumes = [ "/var/www/radarr/data:/config" "/Movies:/movies" "/media/md/Downloads:/downloads" ];
        networks = [ "radarr_default" ];
        extraOptions = [ "--network-alias=radarr" ];
      };

      "sonarr" = {
        image = "lscr.io/linuxserver/sonarr:latest";
        autoStart = true;
        environment = {
          "PGID" = "1000";
          "PUID" = "1000";
          "TZ" = "America/Chicago";
        };
        ports = [ "8989:8989" ];
        volumes = [ "/var/www/sonarr/data:/config" "/TV:/tv" "/media/md/Downloads:/downloads" ];
        networks = [ "sonarr_default" ];
        extraOptions = [ "--network-alias=sonarr" ];
      };

    };
  };

  systemd.services = {
    docker-compose-resources = {
      description = "Create Docker networks and reuse Compose data volumes";
      requires = [ "docker.service" ];
      after = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: driver: ''
          if ! ${docker} network ls --format '{{.Name}}' | ${pkgs.gnugrep}/bin/grep -Fx -- ${lib.escapeShellArg name} > /dev/null; then
            ${docker} network create --driver ${lib.escapeShellArg driver} ${lib.escapeShellArg name}
          fi
        '') networks)}
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: driver: ''
          if ! ${docker} volume ls --format '{{.Name}}' | ${pkgs.gnugrep}/bin/grep -Fx -- ${lib.escapeShellArg name} > /dev/null; then
            ${docker} volume create --driver ${lib.escapeShellArg driver} ${lib.escapeShellArg name}
          fi
        '') volumes)}
      '';
    };
  } // lib.genAttrs (map (name: "docker-${name}") containerNames) (unit: let
    name = lib.removePrefix "docker-" unit;
    paths = bindPaths.${name} or [ ];
  in {
    requires = [ "docker-compose-resources.service" ];
    after = [ "docker-compose-resources.service" ];
    unitConfig.RequiresMountsFor = paths
      ++ lib.optionals (builtins.any (path:
        path == "/media" || path == "/Books" || lib.hasPrefix "/Books/" path
        || path == "/TV" || path == "/Podcasts"
        || lib.hasPrefix "/media/sda/" path
      ) paths) [ "/media/sda" ]
      ++ lib.optionals (builtins.any (path:
        path == "/media" || path == "/Movies" || lib.hasPrefix "/media/md/" path
      ) paths) [ "/media/md" ];
    preStart = lib.mkBefore (lib.concatMapStringsSep "\n" (path: ''
      if [ ! -e ${lib.escapeShellArg path} ]; then
        echo ${lib.escapeShellArg "Missing bind source for ${name}: ${path}"} >&2
        exit 1
      fi
    '') paths);
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = "5s";
      TimeoutStartSec = lib.mkForce 600;
    };
    # Compose's service_healthy dependencies must wait for actual readiness.
    postStart = lib.mkIf (builtins.elem name healthyContainers) ''
      set -euo pipefail
      for attempt in $(${pkgs.coreutils}/bin/seq 1 150); do
        id=$(${docker} container ls --all --filter ${lib.escapeShellArg "name=^/${name}$"} --format '{{.ID}}')
        if [ -z "$id" ]; then
          ${pkgs.coreutils}/bin/sleep 2
          continue
        fi
        state=$(${docker} inspect --format '{{.State.Health.Status}}' ${lib.escapeShellArg name})
        if [ "$state" = healthy ]; then
          exit 0
        fi
        if [ "$state" = unhealthy ]; then
          echo ${lib.escapeShellArg "Container ${name} failed its health check"} >&2
          ${docker} inspect --format '{{json .State.Health}}' ${lib.escapeShellArg name} >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/sleep 2
      done
      echo ${lib.escapeShellArg "Timed out waiting for ${name} to become healthy"} >&2
      exit 1
    '';
  });
}
