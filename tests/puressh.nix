{ pkgs, ... }:
{
  name = "puressh";

  nodes.server = { pkgs, ... }: {
    imports = [ ../shared/puressh.nix ];
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = true;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [ "ashlyn" ];
        MaxAuthTries = 5;
        PerSourcePenalties = "crash:3600s authfail:3600s max:86400s";
      };
    };
    users.users.ashlyn = {
      isNormalUser = true;
      initialPassword = "test-password";
    };
    environment.systemPackages = [ pkgs.python3 ];
  };

  nodes.client = { pkgs, ... }: {
    imports = [ ../shared/puressh.nix ];
    environment.systemPackages = [ pkgs.sshpass pkgs.curl ];
  };

  testScript = ''
    start_all()
    server.wait_for_unit("sshd.service")
    client.wait_for_unit("multi-user.target")
    client.succeed("ssh -V 2>&1 | grep puressh")
    server.succeed("systemctl show sshd -p ExecStart | grep puressh")

    client.succeed("ssh-keygen -q -t ed25519 -N \"\" -f /root/test-key")
    key = client.succeed("cat /root/test-key.pub").strip()
    server.succeed("install -d -m 700 -o ashlyn -g users /home/ashlyn/.ssh")
    server.succeed("echo '%s' > /home/ashlyn/.ssh/authorized_keys" % key)
    server.succeed("chown ashlyn:users /home/ashlyn/.ssh/authorized_keys && chmod 600 /home/ashlyn/.ssh/authorized_keys")
    opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    ssh = "ssh %s -i /root/test-key ashlyn@server" % opts
    client.succeed(ssh + " 'id -un' | grep -x ashlyn")
    client.succeed("sshpass -p test-password ssh %s -o PreferredAuthentications=password -o PubkeyAuthentication=no ashlyn@server 'id -un' | grep -x ashlyn" % opts)
    client.succeed("${pkgs.openssh}/bin/ssh %s -i /root/test-key ashlyn@server 'id -un' | grep -x ashlyn" % opts)
    client.succeed("ssh %s -i /root/test-key -tt ashlyn@server 'test -t 0' </dev/null" % opts)
    client.succeed("echo puressh-test > /root/upload && scp %s -i /root/test-key /root/upload ashlyn@server:/tmp/puressh-upload" % opts)
    server.succeed("grep -x puressh-test /tmp/puressh-upload")
    server.succeed("systemd-run --unit=http-test --property=WorkingDirectory=/tmp ${pkgs.python3}/bin/python -m http.server 8765 --bind 127.0.0.1")
    server.wait_for_open_port(8765)
    client.succeed("ssh %s -i /root/test-key -f -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8766:127.0.0.1:8765 ashlyn@server >/dev/null 2>&1" % opts)
    client.succeed("curl --fail http://127.0.0.1:8766/puressh-upload | grep -x puressh-test")
    client.succeed("ssh %s -i /root/test-key -f -N -T -o ExitOnForwardFailure=yes -D 127.0.0.1:8767 ashlyn@server >/dev/null 2>&1" % opts)
    client.succeed("curl --fail --noproxy \"\" --socks5-hostname 127.0.0.1:8767 http://127.0.0.1:8765/puressh-upload | grep -x puressh-test")
    client.fail("ssh %s -i /root/test-key -o BatchMode=yes root@server true" % opts)
  '';
}
