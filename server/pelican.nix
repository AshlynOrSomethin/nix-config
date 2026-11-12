{ inputs, config, lib, pkgs, ... }:
{
  imports = [
    inputs.pelican-panel.nixosModules.wings
    inputs.pelican-panel.nixosModules.pelican-panel
  ];

  services.pelican-panel = {
    enable = true;
    nginx.enable = true;
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

  systemd.services = {
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
  } // lib.genAttrs [
    "pelican-panel-deploy" "pelican-panel-upgrade" "pelican-panel-queue"
    "pelican-panel-schedule" "phpfpm-pelican-panel"
  ] (_: {
    unitConfig.ConditionPathExists = "/var/lib/shared-mariadb-migration/ready";
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
  });

  # upstream module sets this group on the user but never declares it
  users.groups.pelican-panel = {};
}
