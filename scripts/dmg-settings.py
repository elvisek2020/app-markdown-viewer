# Rozložení okna DMG pro dmgbuild (volá scripts/make-dmg.sh s -D app=… -D background=…).
# Rozměry a pozice ikon sedí se scripts/dmg-background.swift (600 × 420 bodů, středy ikon y = 190).
import os.path

app = defines["app"]  # noqa: F821 – dosazuje dmgbuild
app_name = os.path.basename(app)

format = "UDZO"
compression_level = 9
files = [app]
symlinks = {"Aplikace": "/Applications"}
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")
background = defines["background"]  # noqa: F821

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 160), (600, 420))
default_view = "icon-view"
arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 128
# Bez hide_extensions: přidává aplikaci com.apple.FinderInfo a to rozbije ověření podpisu.
# Finder příponu .app skrývá sám.
icon_locations = {app_name: (150, 190), "Aplikace": (450, 190)}
