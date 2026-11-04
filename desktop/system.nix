{ lib, ... }:

{
  users.users.ashlyn.extraGroups = lib.mkAfter [ "vboxusers" ];
}
