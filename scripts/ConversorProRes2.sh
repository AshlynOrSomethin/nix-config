#!/run/current-system/sw/bin/bash
ICON="$HOME/.prores4linux/icono.png"
TMPDIR_WORK=$(mktemp -d)

python3 /etc/nixos/scripts/conversor_gui.py "$TMPDIR_WORK" "$ICON"

rm -rf "$TMPDIR_WORK"
