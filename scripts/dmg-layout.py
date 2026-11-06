#!/usr/bin/env python3
from pathlib import Path
import sys

from ds_store import DSStore


stage = Path(sys.argv[1])
with DSStore.open(str(stage / ".DS_Store"), "w+") as store:
    store["."]["vSrn"] = ("long", 1)
    store["."]["icvl"] = ("type", b"icnv")
    store["."]["bwsp"] = {
        "WindowBounds": "{{180, 180}, {620, 420}}",
        "ShowToolbar": False,
        "ShowSidebar": False,
        "ContainerShowSidebar": False,
        "ShowStatusBar": False,
        "ShowPathbar": False,
        "ShowTabView": False,
        "PreviewPaneVisibility": False,
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1,
        "backgroundType": 1,
        "backgroundColorRed": 0.965,
        "backgroundColorGreen": 0.973,
        "backgroundColorBlue": 0.985,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": False,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 13.0,
        "iconSize": 96.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }
    store["Secret.app"]["Iloc"] = (165, 145)
    store["Applications"]["Iloc"] = (455, 145)
    store["Read Me.html"]["Iloc"] = (310, 310)
