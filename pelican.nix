{ inputs, config, ... }:
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

  systemd.services.wings.serviceConfig.SupplementaryGroups = [ "nginx" ];

  # upstream module sets this group on the user but never declares it
  users.groups.pelican-panel = {};
}
