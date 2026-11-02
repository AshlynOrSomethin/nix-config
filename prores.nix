{ pkgs, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pygobject3
  ]);

  conversorProRes = pkgs.writeShellScriptBin "conversor-prores" ''
    export PATH="${pkgs.ffmpeg}/bin:${pythonEnv}/bin:$PATH"
    export GI_TYPELIB_PATH="${pkgs.gtk3}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0:${pkgs.pango}/lib/girepository-1.0:${pkgs.gdk-pixbuf}/lib/girepository-1.0:$GI_TYPELIB_PATH"
    export XDG_DATA_DIRS="${pkgs.gtk3}/share:${pkgs.gsettings-desktop-schemas}/share:$XDG_DATA_DIRS"
    
    exec ${pythonEnv}/bin/python3 /etc/nixos/scripts/conversor_gui.py "$@"
  '';

  conversorDesktop = pkgs.makeDesktopItem {
    name = "conversor-prores";
    desktopName = "Conversor ProRes";
    exec = "conversor-prores";
    icon = "video-x-generic";
    terminal = false;
    categories = [ "AudioVideo" "Video" ];
  };
in
{
  environment.systemPackages = [
    conversorProRes
    conversorDesktop
  ];
}
