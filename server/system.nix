{ lib, ... }:

{
  users.users.ashlyn = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... ashlyn@nixos"
    ];
    extraGroups = lib.mkAfter [ "docker" "podman" ];
  };
}
