#!/usr/bin/python3
"""Ask for a new (or existing) words file with the desktop's save dialog.

new-file.py <suggested-folder> <suggested-name>

Omarchy's own chooser, omarchy-file-select, only opens existing files; this is
the same portal call (org.freedesktop.portal.FileChooser) with SaveFile, so a
new file can be named. Prints the chosen path; exit 1 when nothing was picked,
2 when the chooser failed. The file is never truncated: the plugin only
appends to it.
"""
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

ANSWER_TIMEOUT_SEC = 600


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~")
    name = sys.argv[2] if len(sys.argv) > 2 else "words.md"
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    loop = GLib.MainLoop()
    uris = []

    def on_response(connection, sender, path, interface, signal, params):
        code, results = params.unpack()
        if code == 0:
            uris.extend(results.get("uris", []))
        loop.quit()

    def subscribe(path):
        bus.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
                             "Response", path, None, Gio.DBusSignalFlags.NONE, on_response)

    token = "wordcapture%d" % os.getpid()
    sender = bus.get_unique_name()[1:].replace(".", "_")
    predicted = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)
    subscribe(predicted)

    patterns = [(0, "*.md"), (0, "*.markdown"), (0, "*.txt")]
    options = {
        "handle_token": GLib.Variant("s", token),
        "current_name": GLib.Variant("s", name),
        "filters": GLib.Variant("a(sa(us))", [("Markdown", patterns)]),
    }
    if os.path.isdir(folder):
        options["current_folder"] = GLib.Variant("ay", os.fsencode(folder) + b"\0")

    handle = bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                           "org.freedesktop.portal.FileChooser", "SaveFile",
                           GLib.Variant("(ssa{sv})", ("", "Words file", options)),
                           None, Gio.DBusCallFlags.NONE, -1, None).unpack()[0]
    if handle != predicted:
        subscribe(handle)

    GLib.timeout_add_seconds(ANSWER_TIMEOUT_SEC, loop.quit)
    loop.run()

    for uri in uris[:1]:
        print(GLib.filename_from_uri(uri)[0])
    return 0 if uris else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except GLib.Error as error:
        print("new-file.py: %s" % error.message, file=sys.stderr)
        sys.exit(2)
