import os
import plistlib

application = defines["app"]  # noqa: F821
background_image = defines["background"]  # noqa: F821


def icon_from_app(app_path):
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    with open(plist_path, "rb") as plist_file:
        plist = plistlib.load(plist_file)
    icon_name = plist["CFBundleIconFile"]
    icon_root, icon_extension = os.path.splitext(icon_name)
    if not icon_extension:
        icon_extension = ".icns"
    return os.path.join(
        app_path,
        "Contents",
        "Resources",
        icon_root + icon_extension,
    )


format = "UDZO"
filesystem = "HFS+"
compression_level = 9

files = [(application, "hun.app")]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["hun.app"]
icon = icon_from_app(application)

background = background_image
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((100, 100), (660, 400))

default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 80
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 14
icon_size = 128
icon_locations = {
    "hun.app": (170, 230),
    "Applications": (490, 230),
}
