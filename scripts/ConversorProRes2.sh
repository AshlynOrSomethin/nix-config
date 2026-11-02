#!/run/current-system/sw/bin/bash
ICON="$HOME/.prores4linux/icono.png"
TMPDIR_WORK=$(mktemp -d)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$DIR/conversor_gui.py" "$TMPDIR_WORK" "$ICON"

rm -rf "$TMPDIR_WORK"
