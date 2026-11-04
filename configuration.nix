{ host, ... }:
assert builtins.elem host [ "desktop" "server" ];
{
  imports = [
    (if host == "server" then ./server/default.nix else ./desktop/default.nix)
  ];
}
