#!/usr/bin/env bash
# Desktop integration for Polycarbon, the Windows app runner. Run (idempotently) by the
# shell at startup: writes the handler .desktop entry and associates the
# Windows executable MIME types with it — but only types that have no
# default handler yet, so an existing Bottles/Lutris/wine setup is never
# hijacked. Prints one "claimed|<type>" / "kept|<type>|<handler>" line per
# MIME type so the system scan can report the state.
#
#   register.sh <shell-dir>           register handler + free MIME types
#   register.sh <shell-dir> --force   also take over already-claimed types
set -eu

SHELLDIR=${1:?shell dir}
FORCE=${2:-}
DESKTOP_ID="caelestia-polycarbon.desktop"
LEGACY_ID="caelestia-winrun.desktop"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
MIME_TYPES="application/x-ms-dos-executable application/vnd.microsoft.portable-executable application/x-msdownload application/x-msi application/x-ms-shortcut text/x-msdos-batch text/vbscript text/x-ms-regedit"

mkdir -p "$APPS_DIR"
cat > "$APPS_DIR/$DESKTOP_ID" <<EOF
[Desktop Entry]
Type=Application
Name=Polycarbon Windows App
Comment=Runs Windows programs directly, no setup needed
Exec=$SHELLDIR/system/polycarbon/polycarbon %f
Icon=application-x-executable
Terminal=false
NoDisplay=true
MimeType=${MIME_TYPES// /;};
EOF

for type in $MIME_TYPES; do
    current=$(xdg-mime query default "$type" 2>/dev/null || true)
    if [ -z "$current" ] || [ "$current" = "$DESKTOP_ID" ] || [ "$current" = "$LEGACY_ID" ] || [ "$FORCE" = "--force" ]; then
        xdg-mime default "$DESKTOP_ID" "$type"
        echo "claimed|$type"
    else
        echo "kept|$type|$current"
    fi
done

rm -f "$APPS_DIR/$LEGACY_ID"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" || true

# Console entry point: `polycarbon config` (and `polycarbon foo.exe`)
mkdir -p "$HOME/.local/bin"
ln -sfn "$SHELLDIR/system/polycarbon/polycarbon" "$HOME/.local/bin/polycarbon"
