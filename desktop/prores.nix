{ pkgs, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pygobject3
  ]);

  conversorGuiPy = pkgs.writeText "conversor_gui.py" ''
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, GLib
    import sys, os, subprocess, threading, tempfile

    tmpdir = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp()
    ICON = sys.argv[2] if len(sys.argv) > 2 else ""

    VIDEO_EXTS = {'.mp4','.mov','.mkv','.avi','.mpg','.mpeg',
                  '.webm','.flv','.wmv','.dv','.3gp','.3g2',
                  '.gif','.ogv','.m2p','.mpv','.mp2'}

    PROFILES = [
        {"val": 0, "label": "ProRes Proxy", "desc": "Proxy (Smallest file, lowest quality)"},
        {"val": 1, "label": "ProRes LT", "desc": "Light (Good for general offline editing)"},
        {"val": 2, "label": "ProRes 422", "desc": "Standard (Balanced quality/size)"},
        {"val": 3, "label": "ProRes HQ", "desc": "High Quality (Mastering quality)"},
        {"val": 4, "label": "ProRes 4444", "desc": "4444 (Supports Alpha transparency)"},
        {"val": 5, "label": "ProRes 4444 XQ", "desc": "4444 XQ (Maximum data rate)"},
    ]

    class ConversorWindow(Gtk.Window):
        def __init__(self):
            super().__init__(title="Conversor ProRes")
            self.set_default_size(650, 450)
            self.set_position(Gtk.WindowPosition.CENTER)
            self.connect("destroy", lambda _: Gtk.main_quit())

            self.selected_file = None

            vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            vbox.set_margin_top(15)
            vbox.set_margin_bottom(15)
            vbox.set_margin_start(15)
            vbox.set_margin_end(15)
            self.add(vbox)

            # File selection layout
            file_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            self.file_label = Gtk.Label(label="No video selected...", xalign=0)
            self.file_label.set_ellipsize(3) # Pango.EllipsizeMode.MIDDLE
            btn_select = Gtk.Button(label="Choose Video...")
            btn_select.connect("clicked", self.on_choose_file)
            
            file_box.pack_start(self.file_label, True, True, 0)
            file_box.pack_start(btn_select, False, False, 0)
            vbox.pack_start(file_box, False, False, 0)

            # Profile dropdown
            profile_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            profile_label = Gtk.Label(label="Encoding Profile:")
            self.combo = Gtk.ComboBoxText()
            for p in PROFILES:
                self.combo.append_text(p["desc"])
            self.combo.set_active(2) # Default to ProRes 422

            profile_box.pack_start(profile_label, False, False, 0)
            profile_box.pack_start(self.combo, True, True, 0)
            vbox.pack_start(profile_box, False, False, 0)

            # Progress bar & status
            self.progress_bar = Gtk.ProgressBar()
            vbox.pack_start(self.progress_bar, False, False, 0)

            self.status_label = Gtk.Label(label="Ready", xalign=0)
            vbox.pack_start(self.status_label, False, False, 0)

            # Convert Button
            self.btn_convert = Gtk.Button(label="Start Conversion")
            self.btn_convert.set_sensitive(False)
            self.btn_convert.connect("clicked", self.on_convert_clicked)
            vbox.pack_start(self.btn_convert, False, False, 0)

            self.show_all()

        def on_choose_file(self, widget):
            dialog = Gtk.FileChooserDialog(
                title="Select Video File",
                parent=self,
                action=Gtk.FileChooserAction.OPEN
            )
            dialog.add_buttons(
                Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                Gtk.STOCK_OPEN, Gtk.ResponseType.OK
            )
            
            filter_video = Gtk.FileFilter()
            filter_video.set_name("Video Files")
            filter_video.add_mime_type("video/*")
            dialog.add_filter(filter_video)

            response = dialog.run()
            if response == Gtk.ResponseType.OK:
                filename = dialog.get_filename()
                if filename:
                    self.selected_file = filename
                    self.file_label.set_text(filename)
                    self.btn_convert.set_sensitive(True)
            dialog.destroy()

        def on_convert_clicked(self, widget):
            if not self.selected_file:
                return
            
            profile_idx = self.combo.get_active()
            self.btn_convert.set_sensitive(False)
            self.status_label.set_text("Converting...")
            self.progress_bar.set_fraction(0.5) # Simulated activity indicator

            def run_ffmpeg():
                output_file = os.path.splitext(self.selected_file)[0] + "_prores.mov"
                cmd = ["ffmpeg", "-i", self.selected_file, "-c:v", "prores_ks", "-profile:v", str(profile_idx), "-c:a", "pcm_s16le", output_file]
                try:
                    subprocess.run(cmd, check=True)
                    GLib.idle_add(self.conversion_complete, True, output_file)
                except Exception as e:
                    GLib.idle_add(self.conversion_complete, False, str(e))

            threading.Thread(target=run_ffmpeg, daemon=True).start()

        def conversion_complete(self, success, msg):
            self.btn_convert.set_sensitive(True)
            self.progress_bar.set_fraction(1.0)
            if success:
                self.status_label.set_text(f"Success! Saved to: {msg}")
            else:
                self.status_label.set_text(f"Error: {msg}")
            return False

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
