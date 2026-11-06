{ inputs, config, lib, ... }:
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
    wings.serviceConfig.SupplementaryGroups = [ "nginx" ];
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
