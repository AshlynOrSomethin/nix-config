#!/run/current-system/sw/bin/bash
# ============================================================
#  ConversorProRes — v4.0
#  Convierte videos a Apple ProRes
#  Dependencias: ffmpeg, ffprobe, python3-gi
# ============================================================

ICON="$HOME/.prores4linux/icono.png"
TMPDIR_WORK=$(mktemp -d)

python3 - "$TMPDIR_WORK" "$ICON" << 'PYEOF'
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib
import sys, os, subprocess, threading

tmpdir   = sys.argv[1]
ICON     = sys.argv[2]

VIDEO_EXTS = {'.mp4','.mov','.mkv','.avi','.mpg','.mpeg',
              '.webm','.flv','.wmv','.dv','.3gp','.3g2',
              '.gif','.ogv','.m2p','.mpv','.mp2'}

PROFILES = [
  {"val":0,"label":"ProRes\nProxy",
   "desc":"<b>ProRes Proxy</b>  —  El perfil más liviano, pensado para edición offline.\n\n<tt>▸ 4:2:2  ·  10 bits por canal\n▸ ~45 Mb/s (1080p 29.97fps)</tt>\n\n<i>Ideal para proxies de multicámara y equipos con recursos limitados.</i>"},
  {"val":1,"label":"ProRes\nLT",
   "desc":"<b>ProRes LT — Light</b>  —  Mayor calidad que Proxy, archivos compactos.\n\n<tt>▸ 4:2:2  ·  10 bits por canal\n▸ ~102 Mb/s (1080p 29.97fps)</tt>\n\n<i>Ideal para entrega a plataformas y footage de bajo bitrate.</i>"},
  {"val":2,"label":"ProRes\n422",
   "desc":"<b>ProRes 422</b>  —  El perfil estándar broadcast. El más usado en postproducción.\n\n<tt>▸ 4:2:2  ·  10 bits por canal\n▸ ~147 Mb/s (1080p 29.97fps)</tt>\n\n<i>Ideal para postproducción general, broadcast y máster de edición.</i>"},
  {"val":3,"label":"ProRes\nHQ",
   "desc":"<b>ProRes HQ — High Quality</b>  —  Alta calidad para producción exigente.\n\n<tt>▸ 4:2:2  ·  10 bits por canal\n▸ ~220 Mb/s (1080p 29.97fps)</tt>\n\n<i>Ideal para VFX, color grading y entrega a broadcasters premium.</i>"},
  {"val":4,"label":"ProRes\n4444",
   "desc":"<b>ProRes 4444</b>  —  Soporta canal alfa. Para compositing y VFX.\n\n<tt>▸ 4:4:4:4  ·  12 bits/canal imagen  ·  16 bits canal alfa\n▸ ~330 Mb/s (1080p 29.97fps)</tt>\n\n<i>Ideal para motion graphics con alfa y renders de VFX.</i>"},
  {"val":5,"label":"ProRes\n4444 XQ",
   "desc":"<b>ProRes 4444 XQ — Extreme Quality</b>  —  Máxima calidad de Apple.\n\n<tt>▸ 4:4:4:4  ·  12 bits/canal imagen  ·  16 bits canal alfa\n▸ ~500 Mb/s (1080p 29.97fps)</tt>\n\n<i>Ideal para archivado premium, HDR extremo y masters cinematográficos.</i>"},
]

CSS = b"""
window { background-color: #1a1a1a; }
.title-label { color: #ffffff; font-size: 17px; font-weight: bold; }
.subtitle-label { color: #777777; font-size: 11px; }
.section-label { color: #888888; font-size: 10px; font-weight: bold; }
.profile-btn {
  background: #272727; color: #bbbbbb;
  border: 1px solid #383838; border-radius: 7px;
  font-size: 11px; font-weight: 600;
  min-width: 78px; min-height: 50px;
}
.profile-btn:hover { background: #333333; color: #ffffff; border-color: #666; }
.profile-btn.selected { background: #0a7aff; color: #ffffff; border-color: #0a7aff; }
.desc-box {
  background-color: #212121; border-radius: 9px;
  border: 1px solid #2e2e2e; padding: 12px; min-height: 95px;
}
.desc-label { color: #bbbbbb; font-size: 12px; }
.drop-zone {
  background-color: #212121; border-radius: 10px;
  border: 2px dashed #353535; min-height: 90px;
}
.drop-hint { color: #444444; font-size: 13px; }
.file-count { color: #777777; font-size: 11px; }
.btn-primary {
  background: #0a7aff; color: white; border-radius: 7px;
  border: none; font-weight: bold; font-size: 13px; padding: 9px 20px;
}
.btn-primary:hover { background: #2288ff; }
.btn-folder {
  background: #1b341b; color: #55cc55; border-radius: 7px;
  border: 1px solid #2a4a2a; font-weight: bold; font-size: 13px; padding: 9px 18px;
}
.btn-folder:hover { background: #214021; color: #77ee77; }
.btn-secondary {
  background: #272727; color: #777777; border-radius: 7px;
  border: 1px solid #383838; font-size: 12px; padding: 8px 16px;
}
.btn-secondary:hover { color: #cccccc; border-color: #555; }
.btn-danger {
  background: #3a1a1a; color: #cc4444; border-radius: 7px;
  border: 1px solid #5a2a2a; font-size: 12px; font-weight: bold; padding: 8px 16px;
}
.btn-danger:hover { background: #4a2020; color: #ff5555; }
.btn-warn {
  background: #2e2a14; color: #bbaa33; border-radius: 7px;
  border: 1px solid #4a4422; font-size: 12px; padding: 8px 16px;
}
.btn-warn:hover { background: #38331a; color: #ddcc44; }
.row-waiting  { background-color: #222222; border-radius: 6px; }
.row-active   { background-color: #162233; border-radius: 6px; }
.row-done     { background-color: #162216; border-radius: 6px; }
.row-skipped  { background-color: #252520; border-radius: 6px; }
.row-failed   { background-color: #251616; border-radius: 6px; }
.fname-waiting  { color: #cccccc; font-size: 12px; font-weight: 600; }
.fname-active   { color: #7ab8ff; font-size: 12px; font-weight: 600; }
.fname-done     { color: #55cc55; font-size: 12px; }
.fname-skipped  { color: #888855; font-size: 12px; }
.fname-failed   { color: #cc5555; font-size: 12px; }
.row-status { color: #555555; font-size: 10px; }
progressbar trough { background-color: #333333; border-radius: 3px; min-height: 5px; }
progressbar progress { background-color: #0a7aff; border-radius: 3px; }
progressbar.done progress { background-color: #33aa33; }
"""

# ── Estado global compartido entre threads ────────────────────
cancel_current   = threading.Event()
cancel_all       = threading.Event()
current_proc     = [None]   # subprocess.Popen activo

def get_duration(path):
    try:
        r = subprocess.run(
            ["ffprobe","-v","error","-show_entries","format=duration",
             "-of","default=noprint_wrappers=1:nokey=1", path],
            capture_output=True, text=True, timeout=15)
        return max(1, int(float(r.stdout.strip())))
    except:
        return 1

# ════════════════════════════════════════════════════════════
#  VENTANA DE COLA DE RENDERS
# ════════════════════════════════════════════════════════════
class RenderQueueWindow(Gtk.Window):
    def __init__(self, files, profile_val, profile_name):
        super().__init__(title="ConversorProRes — Cola de renders")
        self.set_default_size(660, 540)
        self.set_border_width(0)
        if os.path.exists(ICON):
            self.set_icon_from_file(ICON)
        self.connect("delete-event", self._on_close)

        self.files        = files
        self.profile_val  = profile_val
        self.profile_name = profile_name
        self.row_widgets  = []

        # CSS ya cargado por ConversorWindow; re-aplicar por si se instancia sola
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.set_margin_start(20); outer.set_margin_end(20)
        outer.set_margin_top(18);   outer.set_margin_bottom(16)
        self.add(outer)

        # Cabecera
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        t = Gtk.Label(label="🎬  Cola de renders")
        t.get_style_context().add_class("title-label")
        t.set_halign(Gtk.Align.START)
        hdr.pack_start(t, True, True, 0)
        sub = Gtk.Label(label=f"{profile_name}  ·  {len(files)} archivo{'s' if len(files)!=1 else ''}")
        sub.get_style_context().add_class("subtitle-label")
        sub.set_halign(Gtk.Align.END)
        hdr.pack_start(sub, False, False, 0)
        outer.pack_start(hdr, False, False, 0)
        outer.pack_start(Gtk.Separator(), False, False, 12)

        # Lista scrolleable
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        self.list_box.set_margin_start(2); self.list_box.set_margin_end(2)
        scroll.add(self.list_box)
        outer.pack_start(scroll, True, True, 0)

        for i, f in enumerate(files):
            row = self._build_row(i, f)
            self.list_box.pack_start(row["box"], False, False, 0)
            self.row_widgets.append(row)

        self.list_box.show_all()
        outer.pack_start(Gtk.Separator(), False, False, 12)

        # Barra global
        gl = Gtk.Label(label="PROGRESO GENERAL")
        gl.get_style_context().add_class("section-label")
        gl.set_halign(Gtk.Align.START)
        outer.pack_start(gl, False, False, 2)

        self.global_bar = Gtk.ProgressBar()
        self.global_bar.set_show_text(True)
        self.global_bar.set_text("Iniciando...")
        self.global_bar.set_margin_top(4)
        self.global_bar.set_margin_bottom(12)
        outer.pack_start(self.global_bar, False, False, 0)

        # Botones
        brow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        brow.set_halign(Gtk.Align.END)

        self.btn_skip = Gtk.Button(label="⏭  Cancelar clip actual")
        self.btn_skip.get_style_context().add_class("btn-warn")
        self.btn_skip.connect("clicked", lambda _: cancel_current.set())
        brow.pack_start(self.btn_skip, False, False, 0)

        self.btn_stop = Gtk.Button(label="⏹  Cancelar todos los renders")
        self.btn_stop.get_style_context().add_class("btn-danger")
        self.btn_stop.connect("clicked", self._on_stop_all)
        brow.pack_start(self.btn_stop, False, False, 0)

        outer.pack_start(brow, False, False, 0)
        self.show_all()

        threading.Thread(target=self._run_queue, daemon=True).start()

    def _build_row(self, idx, filepath):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.get_style_context().add_class("row-waiting")
        box.set_margin_start(1); box.set_margin_end(1)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        top.set_margin_start(10); top.set_margin_end(10)
        top.set_margin_top(7);    top.set_margin_bottom(3)

        icon = Gtk.Label(label="⏳")
        top.pack_start(icon, False, False, 0)

        name = Gtk.Label(label=os.path.basename(filepath))
        name.get_style_context().add_class("fname-waiting")
        name.set_halign(Gtk.Align.START)
        name.set_ellipsize(3)
        name.set_hexpand(True)
        top.pack_start(name, True, True, 0)

        status = Gtk.Label(label="En espera")
        status.get_style_context().add_class("row-status")
        status.set_halign(Gtk.Align.END)
        top.pack_start(status, False, False, 0)

        box.pack_start(top, False, False, 0)

        bar = Gtk.ProgressBar()
        bar.set_fraction(0)
        bar.set_show_text(False)
        bar.set_margin_start(10); bar.set_margin_end(10)
        bar.set_margin_bottom(7)
        box.pack_start(bar, False, False, 0)

        return {"box":box, "icon":icon, "name":name, "status":status, "bar":bar}

    def _update_row(self, idx, state, pct=0, status_txt=""):
        row = self.row_widgets[idx]
        box_ctx  = row["box"].get_style_context()
        name_ctx = row["name"].get_style_context()

        for c in ["row-waiting","row-active","row-done","row-skipped","row-failed"]:
            box_ctx.remove_class(c)
        for c in ["fname-waiting","fname-active","fname-done","fname-skipped","fname-failed"]:
            name_ctx.remove_class(c)

        icons = {"waiting":"⏳","active":"🔄","done":"✅","skipped":"⏭","exists":"⏩","failed":"❌"}
        row["icon"].set_text(icons.get(state,"⏳"))

        if state == "active":
            box_ctx.add_class("row-active");   name_ctx.add_class("fname-active")
            row["bar"].set_show_text(True)
            row["bar"].set_fraction(min(pct/100, 1.0))
            row["bar"].set_text(f"{pct}%")
        elif state == "done":
            box_ctx.add_class("row-done");     name_ctx.add_class("fname-done")
            row["bar"].set_fraction(1.0);      row["bar"].set_show_text(False)
        elif state in ("skipped","exists"):
            box_ctx.add_class("row-skipped");  name_ctx.add_class("fname-skipped")
            frac = 1.0 if state=="exists" else 0.0
            row["bar"].set_fraction(frac);     row["bar"].set_show_text(False)
        elif state == "failed":
            box_ctx.add_class("row-failed");   name_ctx.add_class("fname-failed")
            row["bar"].set_fraction(0);        row["bar"].set_show_text(False)
        else:
            box_ctx.add_class("row-waiting");  name_ctx.add_class("fname-waiting")

        if status_txt:
            row["status"].set_text(status_txt)

    def _update_global(self, done, total, ok, fail, skip, clip_pct=100):
        base = (done - 1) / total if total else 0
        within = (clip_pct / 100) / total if total else 0
        self.global_bar.set_fraction(min(1.0, base + within))
        self.global_bar.set_text(
            f"{done}/{total} archivos  ·  ✔ {ok}  ⏭ {skip}  ✖ {fail}")

    def _run_queue(self):
        total = len(self.files)
        ok = fail = skip = 0

        for i, filepath in enumerate(self.files):
            if cancel_all.is_set():
                GLib.idle_add(self._update_row, i, "failed", 0, "Cancelado")
                fail += 1
                continue

            cancel_current.clear()

            # Sanitizar nombre
            d = os.path.dirname(filepath)
            b = os.path.basename(filepath)
            safe = os.path.join(d, b.replace(" ","_"))
            if filepath != safe and not os.path.exists(safe):
                os.rename(filepath, safe)
                filepath = safe

            base, _ = os.path.splitext(filepath)
            output  = base + "-PRORES.mov"

            # Ya existe
            if os.path.exists(output):
                GLib.idle_add(self._update_row, i, "exists", 0, "Ya existe")
                skip += 1
                GLib.idle_add(self._update_global, i+1, total, ok, fail, skip)
                continue

            duration = get_duration(filepath)
            GLib.idle_add(self._update_row, i, "active", 0, "Convirtiendo...")

            cmd = ["ffmpeg","-y","-i",filepath,
                   "-c:v","prores_ks","-profile:v",str(self.profile_val),
                   "-vendor","apl0","-bits_per_mb","8000",
                   "-c:a","pcm_s16le", output]

            proc = subprocess.Popen(cmd, stderr=subprocess.PIPE,
                                    stdout=subprocess.DEVNULL, text=True)
            current_proc[0] = proc
            cancelled = False

            for line in proc.stderr:
                if cancel_current.is_set() or cancel_all.is_set():
                    proc.kill(); cancelled = True; break
                if "time=" in line:
                    try:
                        t = line.split("time=")[1].split()[0]
                        h,m,s = t.split(":")
                        secs = int(h)*3600 + int(m)*60 + int(float(s))
                        pct  = min(100, int(secs*100/duration))
                        GLib.idle_add(self._update_row, i, "active", pct, f"{pct}%")
                        GLib.idle_add(self._update_global, i, total, ok, fail, skip, pct)
                    except: pass

            proc.wait()
            current_proc[0] = None

            if cancelled:
                if os.path.exists(output): os.remove(output)
                if cancel_all.is_set():
                    GLib.idle_add(self._update_row, i, "failed", 0, "Cancelado")
                    fail += 1
                else:
                    GLib.idle_add(self._update_row, i, "skipped", 0, "Clip saltado")
                    skip += 1
            elif proc.returncode == 0:
                GLib.idle_add(self._update_row, i, "done", 100, "Listo ✓")
                ok += 1
            else:
                if os.path.exists(output): os.remove(output)
                GLib.idle_add(self._update_row, i, "failed", 0, "Error")
                fail += 1

            GLib.idle_add(self._update_global, i+1, total, ok, fail, skip)

        GLib.idle_add(self._queue_done, ok, fail, skip, total)

    def _queue_done(self, ok, fail, skip, total):
        self.btn_skip.set_sensitive(False)
        self.btn_stop.set_sensitive(False)
        self.global_bar.set_fraction(1.0)
        self.global_bar.set_text(f"Completado  ·  ✔ {ok}  ⏭ {skip}  ✖ {fail}")

        msg  = f"<b>Conversión completada</b>\n\n"
        msg += f"Archivos en cola:     <b>{total}</b>\n"
        msg += f"Convertidos OK:       <b>{ok}</b>\n"
        if skip: msg += f"Saltados:             <b>{skip}</b>\n"
        if fail: msg += f"Fallidos/Cancelados:  <b>{fail}</b>\n"

        dlg = Gtk.MessageDialog(parent=self, flags=0,
            message_type=Gtk.MessageType.INFO, buttons=Gtk.ButtonsType.OK)
        dlg.set_markup(msg)
        dlg.set_title("ConversorProRes — Listo")
        dlg.run(); dlg.destroy()
        Gtk.main_quit()

    def _on_stop_all(self, btn):
        cancel_all.set(); cancel_current.set()
        self.btn_skip.set_sensitive(False)
        self.btn_stop.set_sensitive(False)

    def _on_close(self, *_):
        cancel_all.set(); cancel_current.set()
        if current_proc[0]:
            try: current_proc[0].kill()
            except: pass
        Gtk.main_quit()
        return False


# ════════════════════════════════════════════════════════════
#  VENTANA PRINCIPAL
# ════════════════════════════════════════════════════════════
class ConversorWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Conversor ProRes")
        self.set_default_size(620, 510)
        self.set_resizable(False)
        self.set_border_width(0)
        self.selected_profile = 3
        self.dropped_files    = []
        self.profile_buttons  = []

        if os.path.exists(ICON):
            self.set_icon_from_file(ICON)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.set_margin_start(22); outer.set_margin_end(22)
        outer.set_margin_top(20);   outer.set_margin_bottom(18)
        self.add(outer)

        # Título
        title = Gtk.Label(label="🎬  Conversor ProRes")
        title.get_style_context().add_class("title-label")
        title.set_halign(Gtk.Align.START)
        outer.pack_start(title, False, False, 0)

        sub = Gtk.Label(label="Seleccioná perfil  ·  arrastrá archivos o elegí una carpeta  ·  convertí")
        sub.get_style_context().add_class("subtitle-label")
        sub.set_halign(Gtk.Align.START)
        outer.pack_start(sub, False, False, 4)
        outer.pack_start(Gtk.Separator(), False, False, 14)

        # Perfil
        pl = Gtk.Label(label="PERFIL DE CODIFICACIÓN")
        pl.get_style_context().add_class("section-label")
        pl.set_halign(Gtk.Align.START)
        outer.pack_start(pl, False, False, 0)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=7)
        btn_row.set_margin_top(7); btn_row.set_margin_bottom(10)
        for p in PROFILES:
            b = Gtk.Button(label=p["label"])
            b.get_style_context().add_class("profile-btn")
            b.set_hexpand(True)
            if p["val"] == self.selected_profile:
                b.get_style_context().add_class("selected")
            b.connect("clicked", self._on_profile, p["val"])
            btn_row.pack_start(b, True, True, 0)
            self.profile_buttons.append((p["val"], b))
        outer.pack_start(btn_row, False, False, 0)

        # Descripción
        db = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        db.get_style_context().add_class("desc-box")
        db.set_margin_bottom(14)
        self.desc_lbl = Gtk.Label()
        self.desc_lbl.get_style_context().add_class("desc-label")
        self.desc_lbl.set_halign(Gtk.Align.START)
        self.desc_lbl.set_valign(Gtk.Align.START)
        self.desc_lbl.set_line_wrap(True)
        self.desc_lbl.set_use_markup(True)
        self.desc_lbl.set_xalign(0)
        db.pack_start(self.desc_lbl, True, True, 0)
        outer.pack_start(db, False, False, 0)
        self._update_desc()

        # Drop zone
        dz_title = Gtk.Label(label="ARCHIVOS DE VIDEO")
        dz_title.get_style_context().add_class("section-label")
        dz_title.set_halign(Gtk.Align.START)
        outer.pack_start(dz_title, False, False, 0)

        self.drop_zone = Gtk.EventBox()
        self.drop_zone.get_style_context().add_class("drop-zone")
        self.drop_zone.set_margin_top(7); self.drop_zone.set_margin_bottom(10)

        dz_inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        dz_inner.set_valign(Gtk.Align.CENTER)
        dz_inner.set_halign(Gtk.Align.CENTER)
        dz_inner.set_margin_top(14); dz_inner.set_margin_bottom(14)

        self.drop_hint = Gtk.Label(label="⬇  Arrastrá archivos de video aquí")
        self.drop_hint.get_style_context().add_class("drop-hint")
        dz_inner.pack_start(self.drop_hint, False, False, 0)

        self.file_count_lbl = Gtk.Label(label="")
        self.file_count_lbl.get_style_context().add_class("file-count")
        self.file_count_lbl.set_line_wrap(True)
        self.file_count_lbl.set_max_width_chars(64)
        dz_inner.pack_start(self.file_count_lbl, False, False, 0)

        self.drop_zone.add(dz_inner)
        outer.pack_start(self.drop_zone, True, True, 0)

        for target in [self.drop_zone, self]:
            target.drag_dest_set(Gtk.DestDefaults.ALL, [], Gdk.DragAction.COPY)
            target.drag_dest_add_uri_targets()
        self.drop_zone.connect("drag-data-received", self._on_drag)
        self.connect("drag-data-received", self._on_drag)

        # Botones de archivo
        fb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        fb.set_halign(Gtk.Align.CENTER)
        fb.set_margin_bottom(14)
        for label, cb in [("📂  Elegir archivos", self._on_browse),
                          ("🗑  Limpiar lista",    self._on_clear)]:
            b = Gtk.Button(label=label)
            b.get_style_context().add_class("btn-secondary")
            b.connect("clicked", cb)
            fb.pack_start(b, False, False, 0)
        outer.pack_start(fb, False, False, 0)

        # Fila de acción
        ar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        ar.set_halign(Gtk.Align.END)

        salir = Gtk.Button(label="Salir")
        salir.get_style_context().add_class("btn-secondary")
        salir.connect("clicked", lambda _: Gtk.main_quit())
        ar.pack_start(salir, False, False, 0)

        btn_folder = Gtk.Button(label="📁  Convertir carpeta")
        btn_folder.get_style_context().add_class("btn-folder")
        btn_folder.connect("clicked", self._on_folder)
        ar.pack_start(btn_folder, False, False, 0)

        btn_conv = Gtk.Button(label="Convertir archivos  🚀")
        btn_conv.get_style_context().add_class("btn-primary")
        btn_conv.connect("clicked", self._on_convert)
        ar.pack_start(btn_conv, False, False, 0)

        outer.pack_start(ar, False, False, 0)
        self.connect("destroy", lambda _: Gtk.main_quit())
        self.show_all()

    def _update_desc(self):
        self.desc_lbl.set_markup(PROFILES[self.selected_profile]["desc"])

    def _on_profile(self, btn, val):
        self.selected_profile = val
        for v, b in self.profile_buttons:
            ctx = b.get_style_context()
            if v == val: ctx.add_class("selected")
            else:        ctx.remove_class("selected")
        self._update_desc()

    def _on_drag(self, widget, ctx, x, y, data, info, time):
        for uri in data.get_uris():
            try:
                path = GLib.filename_from_uri(uri)[0]
                if os.path.isfile(path) and os.path.splitext(path)[1].lower() in VIDEO_EXTS:
                    self.dropped_files.append(path)
            except: pass
        self._refresh_list()

    def _on_browse(self, btn):
        dlg = Gtk.FileChooserDialog(title="Seleccionar videos", parent=self,
                                    action=Gtk.FileChooserAction.OPEN)
        dlg.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                        Gtk.STOCK_OPEN,   Gtk.ResponseType.OK)
        dlg.set_select_multiple(True)
        f = Gtk.FileFilter(); f.set_name("Video")
        for e in VIDEO_EXTS: f.add_pattern(f"*{e}")
        dlg.add_filter(f)
        if dlg.run() == Gtk.ResponseType.OK:
            self.dropped_files.extend(dlg.get_filenames())
            self._refresh_list()
        dlg.destroy()

    def _on_clear(self, btn):
        self.dropped_files = []; self._refresh_list()

    def _refresh_list(self):
        seen = set(); uniq = []
        for f in self.dropped_files:
            if f not in seen: seen.add(f); uniq.append(f)
        self.dropped_files = uniq
        n = len(self.dropped_files)
        if n == 0:
            self.drop_hint.set_text("⬇  Arrastrá archivos de video aquí")
            self.file_count_lbl.set_text("")
        else:
            self.drop_hint.set_text(f"✅  {n} archivo{'s' if n!=1 else ''} en cola")
            names = "\n".join(os.path.basename(f) for f in self.dropped_files[:6])
            if n > 6: names += f"\n... y {n-6} más"
            self.file_count_lbl.set_text(names)

    def _launch_queue(self, files):
        p = PROFILES[self.selected_profile]
        self.hide()
        RenderQueueWindow(files, p["val"], p["label"].replace("\n"," "))

    def _on_convert(self, btn):
        if not self.dropped_files:
            dlg = Gtk.MessageDialog(parent=self, flags=0,
                message_type=Gtk.MessageType.WARNING,
                buttons=Gtk.ButtonsType.OK, text="No hay archivos en la cola.")
            dlg.run(); dlg.destroy(); return
        self._launch_queue(list(self.dropped_files))

    def _on_folder(self, btn):
        dlg = Gtk.FileChooserDialog(title="Seleccionar carpeta", parent=self,
                                    action=Gtk.FileChooserAction.SELECT_FOLDER)
        dlg.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                        Gtk.STOCK_OPEN,   Gtk.ResponseType.OK)
        if dlg.run() != Gtk.ResponseType.OK:
            dlg.destroy(); return
        folder = dlg.get_filename(); dlg.destroy()

        files = sorted([
            os.path.join(folder, f) for f in os.listdir(folder)
            if os.path.splitext(f)[1].lower() in VIDEO_EXTS
            and "-PRORES" not in f
        ])

        if not files:
            dlg2 = Gtk.MessageDialog(parent=self, flags=0,
                message_type=Gtk.MessageType.WARNING,
                buttons=Gtk.ButtonsType.OK,
                text=f"No se encontraron videos en:\n{folder}")
            dlg2.run(); dlg2.destroy(); return

        self._launch_queue(files)

# ── Entry point ───────────────────────────────────────────────
ConversorWindow()
Gtk.main()
PYEOF

rm -rf "$TMPDIR_WORK"
