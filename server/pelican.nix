{ inputs, config, lib, pkgs, ... }:
let
  panel = config.services.pelican-panel;
  panelPackage = inputs.pelican-panel.packages.${pkgs.stdenv.hostPlatform.system}.pelican-panel;
  panelTools = [
    pkgs.yarn
    pkgs.nodejs
    pkgs.php
    pkgs.php.packages.composer
    pkgs.git
    pkgs.unzip
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
  ];
  panelPath = lib.makeBinPath panelTools;
  panelHome = "${panel.runtimeLocation}/storage";
  # Pelican builds theme assets at runtime; preserve them between deployments.
  rebuildPanelAssets = pkgs.writeShellScript "pelican-panel-rebuild-assets" ''
    set -euo pipefail
    cd ${lib.escapeShellArg (toString panel.runtimeLocation)}
    yarn install --non-interactive
    yarn build
  '';
  deployPanel = pkgs.writeShellScript "pelican-panel-deploy" ''
    set -euo pipefail
    runtime=${lib.escapeShellArg (toString panel.runtimeLocation)}
    source=${lib.escapeShellArg "${panelPackage}/share/php/pelican-panel"}
    marker="$runtime/storage/.deployed-panel-package"

    ${pkgs.coreutils}/bin/mkdir -p "$runtime"/{bootstrap/cache,storage/app/private,storage/app/public,storage/framework/cache,storage/framework/sessions,storage/framework/testing,storage/framework/views,storage/logs,public/build,plugins}
    ${pkgs.rsync}/bin/rsync -a --delete \
      --exclude='/.env' --exclude='/storage' --exclude='/database/database.sqlite' \
      --exclude='/plugins' --exclude='/node_modules' --exclude='/public/build' \
      "$source/" "$runtime/"
    ${pkgs.coreutils}/bin/chown -R ${lib.escapeShellArg "${panel.user}:${panel.group}"} "$runtime"
    ${pkgs.coreutils}/bin/chmod -R 755 "$runtime"
    HOME=/tmp COMPOSER_HOME=/tmp ${pkgs.php.packages.composer}/bin/composer dump-autoload --working-dir="$runtime" --no-interaction

    if [ ! -f "$marker" ] || [ "$(< "$marker")" != "$source" ] || [ ! -f "$runtime/public/build/manifest.json" ]; then
      if [ -n "$(${pkgs.findutils}/bin/find "$runtime/plugins" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]; then
        ${pkgs.util-linux}/bin/runuser -u ${lib.escapeShellArg panel.user} -- \
          ${pkgs.coreutils}/bin/env HOME=${lib.escapeShellArg panelHome} PATH=${lib.escapeShellArg panelPath} \
          ${rebuildPanelAssets}
      else
        ${pkgs.rsync}/bin/rsync -a --checksum --delete "$source/public/build/" "$runtime/public/build/"
        ${pkgs.coreutils}/bin/chown -R ${lib.escapeShellArg "${panel.user}:${panel.group}"} "$runtime/public/build"
        ${pkgs.coreutils}/bin/chmod -R 755 "$runtime/public/build"
      fi
      printf '%s\n' "$source" > "$marker"
      ${pkgs.coreutils}/bin/chown ${lib.escapeShellArg "${panel.user}:${panel.group}"} "$marker"
    fi
  '';
in
{
  imports = [
    inputs.pelican-panel.nixosModules.wings
    inputs.pelican-panel.nixosModules.pelican-panel
  ];

  services.pelican-panel = {
    enable = true;
    nginx.enable = true;
  };

  services.phpfpm.pools.${panel.phpfpm.poolName}.phpEnv = {
    HOME = panelHome;
    PATH = panelPath;
  };

  services.wings = {
    enable = true;
    containerBackend = "podman";
    node = {
      uuid = "bcb48c41-4ca2-4628-837c-c9e7c496c087";
      tokenId = "120xGHxED7dln0wI";
      # Recommended to use sops or another form of encrypting this value
      tokenPath = "/var/lib/secrets/wings-token";
      remote = "https://panel.pulsar.ltd";
      api = {
        port = 8443;
        ssl = {
          enabled = true;
          cert = "/etc/ssl/pulsar.ltd/pulsar.ltd.pem";
          key = "/etc/ssl/pulsar.ltd/pulsar.ltd.key";
        };
      };
    };
  };

  systemd.services = lib.mkMerge [ {
    pelican-panel-deploy = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig.ExecStart = lib.mkForce [ "${deployPanel}" ];
    };
    pelican-panel-queue = {
      path = panelTools;
      environment.HOME = panelHome;
    };
    podman-pelican-network = {
      description = "Create the Podman network for Wings";
      requires = [ "podman.socket" ];
      after = [ "podman.socket" ];
      before = [ "wings.service" ];
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      path = [ config.virtualisation.podman.package pkgs.jq ];
      script = ''
        if podman network exists pelican_nw; then
          podman network inspect pelican_nw | jq -e '
            .[0] |
            .network_interface == "pelican-pod0" and
            .ipv6_enabled == true and
            ([.subnets[] | .subnet] | sort) == (["10.245.0.0/24", "fd42:9c5e:3510::/64"] | sort)
          ' >/dev/null || {
            echo "Existing Podman pelican_nw does not match the Wings network configuration" >&2
            exit 1
          }
        else
          status=$?
          if [ "$status" -ne 1 ]; then
            echo "Could not check the Podman Wings network (exit $status)" >&2
            exit "$status"
          fi
          podman network create --interface-name pelican-pod0 \
            --subnet 10.245.0.0/24 --gateway 10.245.0.1 \
            --ipv6 --subnet fd42:9c5e:3510::/64 --gateway fd42:9c5e:3510::1 \
            pelican_nw
        fi
      '';
    };
    wings = {
      requires = [ "podman-pelican-network.service" ];
      after = [ "podman-pelican-network.service" ];
      serviceConfig.SupplementaryGroups = [ "nginx" ];
    };
  } (lib.genAttrs [
    "pelican-panel-deploy" "pelican-panel-upgrade" "pelican-panel-queue"
    "pelican-panel-schedule" "phpfpm-pelican-panel"
  ] (_: {
    unitConfig.ConditionPathExists = "/var/lib/shared-mariadb-migration/ready";
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
  })) ];

  # upstream module sets this group on the user but never declares it
  users.groups.pelican-panel = {};
}
