{ pkgs, ... }:
let
  image = pkgs.dockerTools.buildLayeredImage {
    name = "podman-migration-test";
    tag = "latest";
    contents = [ pkgs.busybox ];
    config.Cmd = [ "/bin/sleep" "600" ];
  };
in
{
  name = "podman-container-resources";

  nodes.server = { lib, ... }: {
    imports = [ ../server/docker.nix ];
    virtualisation.oci-containers.containers = (lib.genAttrs [
      "authentik-server-1" "authentik-worker-1" "bazarr" "bitmagnet" "chiyogami"
      "freshrss" "grimmory" "grimmory-mariadb-1" "iqbit" "radarr" "sonarr"
    ] (_: {
      autoStart = lib.mkForce false;
    })) // {
      freshrss = {
        autoStart = lib.mkForce false;
        image = lib.mkForce "localhost/podman-migration-test:latest";
        pull = lib.mkForce "never";
      };
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")
    server.fail("systemctl start podman-container-resources.service")
    server.succeed("mkdir -p /var/lib/podman-container-migration && touch /var/lib/podman-container-migration/ready")
    server.fail("systemctl start podman-container-resources.service")
    server.succeed("podman volume create freshrss_data && podman volume create freshrss_extensions")
    server.succeed("systemctl reset-failed podman-container-resources.service")
    server.succeed("systemctl start podman-container-resources.service")
    server.succeed("podman network inspect grimmory_default | grep -q 10.246.6.0/24")
    server.succeed("systemctl restart podman-container-resources.service")
    server.succeed("systemctl is-active --quiet podman-container-resources.service")
    server.succeed("mkdir -p /run/postgresql /var/www/FreshRSS")
    server.succeed("podman load -i ${image}")
    server.succeed("systemctl start podman-freshrss.service")
    server.succeed("podman exec freshrss cat /etc/hosts | grep -q host.docker.internal")
    server.succeed("systemctl stop podman-freshrss.service")
  '';
}
