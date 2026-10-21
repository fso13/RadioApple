"""dmgbuild settings for the RadioMac drag-and-drop installer window.

Used by `scripts/make_installer.sh`:

    dmgbuild -s scripts/dmg_settings.py \
        -D app=.../RadioMac.app \
        -D background=installer/background.png \
        -D volume_icon=installer/RadioMac.icns \
        "RadioMac 1.0.0" dist/RadioMac-1.0.0.dmg

`defines` is provided by dmgbuild.
"""

import os

app = defines["app"]
app_name = os.path.basename(app)
background = defines.get("background")
volume_icon = defines.get("volume_icon")

files = [app]
symlinks = {"Applications": "/Applications"}

# The background artwork is drawn for these two anchor points (points).
icon_locations = {
    app_name: (170, 195),
    "Applications": (470, 195),
}

background = background
icon = volume_icon

window_rect = ((240, 160), (640, 400))
default_view = "icon-view"
icon_size = 96
text_size = 13
label_pos = "bottom"
show_toolbar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
grid_spacing = 100

format = "UDZO"
filesystem = "HFS+"
