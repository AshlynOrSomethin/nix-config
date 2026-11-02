{ pkgs, ... }:

let
  conversorProRes = pkgs.writeShellScriptBin "conversor-prores" ''
    export PATH="${pkgs.ffmpeg}/bin:${pkgs.python3}/bin:$PATH"
    exec ${pkgs.python3}/bin/python3 /etc/nixos/scripts/ConversorProRes2.sh "$@"
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
