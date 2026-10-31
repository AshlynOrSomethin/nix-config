{
  fileSystems."/mount/xali" = {
    device = "ashlyn@xali.host:/home/ashlyn";
    fsType = "fuse.sshfs";
    options = [
      "_netdev"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "x-systemd.mount-timeout=30s"
      "IdentityFile=/home/ashlyn/.ssh/id_ed25519"
      "UserKnownHostsFile=/home/ashlyn/.ssh/known_hosts"
      "StrictHostKeyChecking=yes"
      "BatchMode=yes"
      "IdentitiesOnly=yes"
      "IdentityAgent=none"
      "ConnectTimeout=15"
      "ServerAliveInterval=15"
      "ServerAliveCountMax=3"
      "reconnect"
      "allow_other"
      "default_permissions"
      "uid=1000"
      "gid=100"
      "umask=077"
      "nodev"
      "nosuid"
      "noexec"
    ];
  };
}
