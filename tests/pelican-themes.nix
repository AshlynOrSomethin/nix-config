{ inputs, pkgs, ... }:
{
  name = "pelican-themes";
  node.pkgsReadOnly = false;

  nodes.server = { lib, ... }: {
    imports = [ ({ config, lib, pkgs, ... }@args: import ../server/pelican.nix (args // { inherit inputs config lib pkgs; })) ];
    nixpkgs.overlays = [
      (final: prev: {
        yarn = prev.writeShellScriptBin "yarn" ''
          set -eu
          test "$HOME" = /srv/http/pelican-panel/storage
          test "$(id -un)" = pelican-panel
          case "$1" in
            install) test ! -f storage/fail-theme-build ;;
            build) echo rebuilt-theme > public/build/manifest.json ;;
            *) exit 1 ;;
          esac
        '';
      })
    ];
    services.wings.enable = lib.mkForce false;
    virtualisation.podman.enable = true;
    systemd.targets.postgresql = { };
    virtualisation.memorySize = 2048;
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")
    server.succeed("mkdir -p /var/lib/shared-mariadb-migration && touch /var/lib/shared-mariadb-migration/ready")
    server.succeed("systemctl start pelican-panel-deploy.service")
    server.succeed("test -s /srv/http/pelican-panel/public/build/manifest.json")
    server.succeed("test -s /srv/http/pelican-panel/storage/.deployed-panel-package")
    server.succeed("""printf '%s\\n' '<?php echo getenv("HOME"), "\\n", shell_exec("command -v yarn");' > /srv/http/pelican-panel/public/theme-test.php""")
    server.wait_for_unit("phpfpm-pelican-panel.service")
    server.wait_for_open_port(8080)
    server.succeed("${pkgs.curl}/bin/curl -fsS http://127.0.0.1:8080/theme-test.php | grep -q /srv/http/pelican-panel/storage")
    server.succeed("${pkgs.curl}/bin/curl -fsS http://127.0.0.1:8080/theme-test.php | grep -q /bin/yarn")
    server.succeed("systemctl show pelican-panel-queue.service -p Environment | grep -q 'yarn.*/bin'")
    server.succeed("mkdir -p /srv/http/pelican-panel/plugins/theme /srv/http/pelican-panel/node_modules/test")
    server.succeed("echo plugin > /srv/http/pelican-panel/plugins/theme/plugin.json")
    server.succeed("echo dependency > /srv/http/pelican-panel/node_modules/test/file")
    server.succeed("echo installed-theme > /srv/http/pelican-panel/public/build/manifest.json")
    server.succeed("systemctl restart pelican-panel-deploy.service")
    server.succeed("grep -q installed-theme /srv/http/pelican-panel/public/build/manifest.json")
    server.succeed("test -f /srv/http/pelican-panel/plugins/theme/plugin.json")
    server.succeed("test -f /srv/http/pelican-panel/node_modules/test/file")
    server.succeed("echo old-package > /srv/http/pelican-panel/storage/.deployed-panel-package")
    server.succeed("systemctl restart pelican-panel-deploy.service")
    server.succeed("grep -q rebuilt-theme /srv/http/pelican-panel/public/build/manifest.json")
    server.succeed("test -f /srv/http/pelican-panel/plugins/theme/plugin.json")
    server.succeed("echo old-package > /srv/http/pelican-panel/storage/.deployed-panel-package")
    server.succeed("touch /srv/http/pelican-panel/storage/fail-theme-build")
    server.fail("systemctl restart pelican-panel-deploy.service")
    server.succeed("grep -qx old-package /srv/http/pelican-panel/storage/.deployed-panel-package")
  '';
}
