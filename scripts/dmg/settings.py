# dmgbuild settings for Fokly's disk image: the app, an Applications link and the background
# from background.py, in a 640×400 window without toolbars. Called by scripts/release.sh:
#   dmgbuild -s scripts/dmg/settings.py -D app=… -D background=… Fokly out.dmg
import os

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")
format = "ULFO"

background = defines["background"]
window_rect = ((240, 160), (640, 432))  # 400 pt of content under the 32 pt title bar
default_view = "icon-view"
show_status_bar = show_tab_view = show_toolbar = show_pathbar = show_sidebar = False
include_icon_view_settings = True
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {"Fokly.app": (180, 170), "Applications": (460, 170)}
hide_extension = ["Fokly.app"]
