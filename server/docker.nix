{ config, lib, pkgs, ... }:

# Systemd replaces Compose as the container supervisor. Keep the runtime
# environment files in /var/lib/docker-compose-env backed up separately.
let
  podman = "${config.virtualisation.podman.package}/bin/podman";
  containerNames = [ "authentik-server-1" "authentik-worker-1" "bazarr" "bitmagnet" "chiyogami" "freshrss" "grimmory" "grimmory-mariadb-1" "iqbit" "radarr" "sonarr" ];
  healthyContainers = [ "grimmory-mariadb-1" ];
  networks = {
    "authentik_default" = "10.246.1.0/24";
    "bazarr_default" = "10.246.2.0/24";
    "bitmagnet_default" = "10.246.3.0/24";
    "chiyogami_default" = "10.246.4.0/24";
    "freshrss_default" = "10.246.5.0/24";
    "grimmory_default" = "10.246.6.0/24";
    "radarr_default" = "10.246.7.0/24";
    "sonarr_default" = "10.246.8.0/24";
  };
  bindPaths = {
    "authentik-server-1" = [ "/run/postgresql" "/etc/docker-compose/authentik/data" "/etc/docker-compose/authentik/custom-templates" ];
    "authentik-worker-1" = [ "/run/postgresql" "/run/podman/podman.sock" "/etc/docker-compose/authentik/data" "/etc/docker-compose/authentik/certs" "/etc/docker-compose/authentik/custom-templates" ];
    "bazarr" = [ "/var/www/bazarr/config" "/Movies" "/TV" ];
    "bitmagnet" = [ "/run/postgresql" ];
    "chiyogami" = [ "/etc/docker-compose/chiyogami/pastes" ];
    "freshrss" = [ "/run/postgresql" "/var/www/FreshRSS" ];
    "grimmory" = [ "/etc/docker-compose/grimmory/data" "/Books" "/etc/docker-compose/grimmory/bookdrop" ];
    "grimmory-mariadb-1" = [ "/etc/docker-compose/grimmory/mariadb/config" ];
    "iqbit" = [ "/etc/docker-compose/iQbit/server.js" ];
    "radarr" = [ "/var/www/radarr/data" "/Movies" "/media/md/Downloads" ];
    "sonarr" = [ "/var/www/sonarr/data" "/TV" "/media/md/Downloads" ];
  };
in
{
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      # Secret values live in root-only environment files, never in the Nix store.
      "authentik-server-1" = {
        image = "ghcr.io/goauthentik/server:2026.8.3";
        autoStart = true;
        environment = {
          "AUTHENTIK_POSTGRESQL__HOST" = "/run/postgresql";
          "AUTHENTIK_POSTGRESQL__NAME" = "authentik";
          "AUTHENTIK_POSTGRESQL__USER" = "authentik";
          "COMPOSE_PORT_HTTP" = "9180";
          "COMPOSE_PORT_HTTPS" = "9143";
        };
        environmentFiles = [ "/var/lib/native-services-migration/authentik-server-1.env" ];
        ports = [ "9180:9000" "9143:9443" ];
        volumes = [ "/run/postgresql:/run/postgresql:ro" "/etc/docker-compose/authentik/data:/data" "/etc/docker-compose/authentik/custom-templates:/templates" ];
        networks = [ "authentik_default" ];
        cmd = [ "server" ];
        extraOptions = [ "--network-alias=server" "--shm-size=536870912" ];
      };

      "authentik-worker-1" = {
        image = "ghcr.io/goauthentik/server:2026.8.3";
        autoStart = true;
        environment = {
          "AUTHENTIK_POSTGRESQL__HOST" = "/run/postgresql";
          "AUTHENTIK_POSTGRESQL__NAME" = "authentik";
          "AUTHENTIK_POSTGRESQL__USER" = "authentik";
          "COMPOSE_PORT_HTTP" = "9180";
          "COMPOSE_PORT_HTTPS" = "9143";
        };
        environmentFiles = [ "/var/lib/native-services-migration/authentik-worker-1.env" ];
        volumes = [ "/run/postgresql:/run/postgresql:ro" "/run/podman/podman.sock:/var/run/docker.sock" "/etc/docker-compose/authentik/data:/data" "/etc/docker-compose/authentik/certs:/certs" "/etc/docker-compose/authentik/custom-templates:/templates" ];
        networks = [ "authentik_default" ];
        cmd = [ "worker" ];
        user = "root";
        extraOptions = [ "--network-alias=worker" "--shm-size=536870912" ];
      };

      "bazarr" = {
        image = "lscr.io/linuxserver/bazarr:latest";
        autoStart = false;
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
          "POSTGRES_HOST" = "/run/postgresql";
          "POSTGRES_USER" = "bitmagnet";
          "POSTGRES_NAME" = "bitmagnet";
        };
        environmentFiles = [ "/var/lib/native-services-migration/bitmagnet.env" ];
        ports = [ "3333:3333" "3334:3334" "3334:3334/udp" ];
        networks = [ "bitmagnet_default" ];
        volumes = [ "/run/postgresql:/run/postgresql:ro" ];
        cmd = [ "worker" "run" "--keys=http_server" "--keys=queue_server" "--keys=dht_crawler" ];
        extraOptions = [ "--network-alias=bitmagnet" ];
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
        volumes = [ "/run/postgresql:/run/postgresql:ro" "/var/www/FreshRSS:/config" "freshrss_data:/var/www/FreshRSS/data" "freshrss_extensions:/var/www/FreshRSS/extensions" ];
        networks = [ "freshrss_default" ];
        extraOptions = [ "--network-alias=freshrss" "--add-host=host.docker.internal:host-gateway" ];
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
          "QBIT_HOST" = "http://127.0.0.1:8085";
          "STANDALONE_SERVER_PORT" = "8082";
        };
        volumes = [ "/etc/docker-compose/iQbit/server.js:/usr/src/node-app/server/server.js:ro,Z" ];
        extraOptions = [ "--network=host" ];
      };

      "radarr" = {
        image = "lscr.io/linuxserver/radarr:latest";
        autoStart = false;
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
        autoStart = false;
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
    podman-container-resources = {
      description = "Create Podman container networks";
      requires = [ "podman.socket" ];
      after = [ "podman.socket" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        if [ ! -f /var/lib/podman-container-migration/ready ]; then
          echo "Podman migration has not been prepared; refusing to start application containers" >&2
          exit 1
        fi
        for volume in freshrss_data freshrss_extensions; do
          if ! ${podman} volume exists "$volume"; then
            echo "Missing migrated Podman volume: $volume" >&2
            exit 1
          fi
        done
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: subnet: ''
          if ${podman} network exists ${lib.escapeShellArg name}; then
            ${podman} network inspect ${lib.escapeShellArg name} | ${pkgs.jq}/bin/jq -e \
              --arg subnet ${lib.escapeShellArg subnet} '.[0].dns_enabled == true and ([.[0].subnets[].subnet] == [$subnet])' >/dev/null
          else
            status=$?
            if [ "$status" -ne 1 ]; then
              echo "Cannot check Podman network ${name}: $status" >&2
              exit "$status"
            fi
            ${podman} network create --subnet ${lib.escapeShellArg subnet} ${lib.escapeShellArg name}
          fi
        '') networks)}
      '';
    };
  } // lib.genAttrs (map (name: "podman-${name}") containerNames) (unit: let
    name = lib.removePrefix "podman-" unit;
    paths = bindPaths.${name} or [ ];
  in {
    requires = [ "podman-container-resources.service" ];
    after = [ "podman-container-resources.service" ];
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
        id=$(${podman} container ls --all --filter ${lib.escapeShellArg "name=^${name}$"} --format '{{.ID}}')
        if [ -z "$id" ]; then
          ${pkgs.coreutils}/bin/sleep 2
          continue
        fi
        state=$(${podman} inspect --format '{{.State.Health.Status}}' ${lib.escapeShellArg name})
        if [ "$state" = healthy ]; then
          exit 0
        fi
        if [ "$state" = unhealthy ]; then
          echo ${lib.escapeShellArg "Container ${name} failed its health check"} >&2
          ${podman} inspect --format '{{json .State.Health}}' ${lib.escapeShellArg name} >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/sleep 2
      done
      echo ${lib.escapeShellArg "Timed out waiting for ${name} to become healthy"} >&2
      exit 1
    '';
  });
}
