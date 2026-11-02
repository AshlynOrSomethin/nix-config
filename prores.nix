{ pkgs, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pygobject3
  ]);

  conversorGuiPy = pkgs.writeText "conversor_gui.py" ''
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, GLib
    import sys, os, subprocess, threading

    tmpdir = sys.argv[1]
    ICON = sys.argv[2]

    class ConversorWindow(Gtk.Window):
        def __init__(self):
            super().__init__(title="Conversor ProRes")
            self.set_default_size(620, 510)
            self.connect("destroy", lambda _: Gtk.main_quit())
            label = Gtk.Label(label="Conversor ProRes Initialized Successfully ✓")
            self.add(label)
            self.show_all()

    ConversorWindow()
    Gtk.main()
  '';

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
      mkdir -p $out/bin
      makeWrapper ${pythonEnv}/bin/python3 $out/bin/conversor-prores \
        --add-flags "${conversorGuiPy}" \
        --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.ffmpeg pythonEnv ]}"
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
