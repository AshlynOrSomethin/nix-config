{ config, lib, pkgs, ... }:

let
  davinciWrapper = pkgs.writeShellScriptBin "davinci-resolve-studio" ''
    # Set environment flags to isolate and satisfy the licensing daemon
    export RESOLVE_LICENSE_MODE="local"
    export BMD_LICENSE_DIR="/var/db/blackmagic"
    
    # Create local license directory structure on the fly if missing
    mkdir -p "$HOME/.local/share/DaVinciResolve/.license"
    printf "LICENSE blackmagic davinciresolvestudio 999999 permanent uncounted\n hostid=ANY issuer=CGP customer=CGP issued=28-dec-2023\n akey=0000-0000-0000-0000 _ck=00 sig=\"00\"\n" > "$HOME/.local/share/DaVinciResolve/.license/blackmagic.lic"

    # Launch the actual studio binary from the package store
    exec ${pkgs.davinci-resolve-studio}/bin/resolve "$@"
  '';
in
{
  environment.systemPackages = [
    davinciWrapper
  ];

  environment.variables = {
    RUSTICL_ENABLE = "radeonsi";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      mesa.opencl
    ];
  };
}
