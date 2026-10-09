#!/bin/bash
# Poco X8 Pro (klee) display tweaks for Lomiri (UT 24.04-1.x has no cutout support).
# Panel: 1268x2756, centred punch-hole camera 78x102 px at the top, 190 px corner radius
# (values from Axion's FrameworksResOverlayKlee: config_mainBuiltInDisplayCutout,
#  rounded_corner_radius).
#   * status bar height: max(3 GU, 120 px)  -> clears the 102 px camera hole
#   * 64 px side insets for the status bar rows -> icons stay out of the rounded corners
# usage: lomiri-klee.sh <rootfs mountpoint>   (idempotent)
set -euo pipefail
R="${1:?rootfs}/usr/share/lomiri"
PANEL_PX=120
INSET_PX=64

if ! grep -q "// klee: clear the punch-hole camera" "$R/Shell.qml"; then
	sed -i "s|^\(\s*\)minimizedPanelHeight: units.gu(3)$|\1minimizedPanelHeight: Math.max(units.gu(3), $PANEL_PX) // klee: clear the punch-hole camera|" "$R/Shell.qml"
fi
[ "$(grep -c "// klee: clear the punch-hole camera" "$R/Shell.qml")" = 1 ] \
	|| { echo "lomiri-klee: Shell.qml patch failed" >&2; exit 1; }

python3 - "$R/Panel/PanelMenu.qml" "$INSET_PX" <<'PY'
import sys
p, inset = sys.argv[1], sys.argv[2]
s = open(p).read()
old = """    PanelBar {
        id: bar
        objectName: "indicatorsBar"

        anchors {
            left: parent.left
            right: parent.right
        }"""
new = """    PanelBar {
        id: bar
        objectName: "indicatorsBar"

        anchors {
            left: parent.left
            right: parent.right
            // klee: keep the status bar icons out of the 190 px rounded corners
            leftMargin: %s
            rightMargin: %s
        }""" % (inset, inset)
if "// klee: keep the status bar icons" in s:
    sys.exit(0)
if old not in s:
    sys.exit("lomiri-klee: PanelMenu.qml pattern not found")
open(p, "w").write(s.replace(old, new))
PY
echo "lomiri-klee: applied (panel ${PANEL_PX}px, insets ${INSET_PX}px)"
