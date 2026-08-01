# -*- coding: utf-8 -*-
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, r"H:\game_dev\eveautochess-dev\tools")
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

info = Path(fetch_resfile("res:/audio/soundbanksinfo.json"))
data = json.loads(info.read_text("utf-8", errors="replace"))
print("top keys", list(data.keys())[:20] if isinstance(data, dict) else type(data))

# Walk structure for SoundBanks / StreamedFiles / Event hierarchy
text = info.read_text("utf-8", errors="replace")

# Find NPCdeath / fire_wreck / asteroid_death context windows
for needle in [
    "NPCdeath_L",
    "NPCdeath_m1_body",
    "fire_wreck",
    "asteroid_death_explosion",
    "poddeath",
    "npc-death-8",
    "target_destroy",
]:
    i = text.find(needle)
    print("====", needle, "at", i)
    if i >= 0:
        print(text[max(0, i - 300) : i + 400].replace("\n", " | "))
