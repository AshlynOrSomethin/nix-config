{ pkgs, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pygobject3
  ]);

  conversorProRes = pkgs.stdenv.mkDerivation {
    name = "conversor-prores";
    dontUnpack = true;

    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
    ];

    buildInputs = [
      pythonEnv
      pkgs.ffmpeg
      pkgs.gtk3
      pkgs.pango
      pkgs.gdk-pixbuf
      pkgs.atk
      pkgs.glib
      pkgs.gsettings-desktop-schemas
    ];

    installPhase = ''
      mkdir -p $out/bin $out/share/conversor-prores
      cp ./scripts/ConversorProRes2.sh $out/share/conversor-prores/
      cp ./scripts/conversor_gui.py $out/share/conversor-prores/
      chmod +x $out/share/conversor-prores/ConversorProRes2.sh

      makeWrapper $out/share/conversor-prores/ConversorProRes2.sh $out/bin/conversor-prores \
        --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.ffmpeg pythonEnv ]}" \
        --set PYTHONEXECUTABLE "${pythonEnv}/bin/python3"
    '';
  };

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
