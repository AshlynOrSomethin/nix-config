{ pkgs, ... }:

let
  # Create a python environment wrapper that includes pygobject3 (gi)
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pygobject3
  ]);

  conversorProRes = pkgs.writeShellScriptBin "conversor-prores" ''
    export PATH="${pkgs.ffmpeg}/bin:${pythonEnv}/bin:$PATH"
    exec ${pythonEnv}/bin/python3 /etc/nixos/scripts/ConversorProRes2.sh "$@"
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
