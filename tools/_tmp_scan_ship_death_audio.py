# -*- coding: utf-8 -*-
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, r"H:\game_dev\eveautochess-dev\tools")
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

info = Path(fetch_resfile("res:/audio/soundbanksinfo.json"))
text = info.read_text("utf-8", errors="replace")
print("soundbanksinfo", info, "len", len(text))

# Event / object names mentioning death/explosion
pat = re.compile(
    r'"(Name|ObjectPath|ShortName|Path|Id)":\s*"([^"]*(?:[Dd]eath|[Ee]xplod|[Dd]estroy|[Ww]reck|[Bb]oom|[Kk]ill)[^"]*)"'
)
hits = pat.findall(text)
seen = []
for _k, v in hits:
    if v not in seen:
        seen.append(v)
print("name hits", len(seen))
for v in seen[:100]:
    print(v)

banks = sorted(set(re.findall(r"res:/audio/[^\"]+\.bnk", text, flags=re.I)))
print("banks", len(banks))
for b in banks:
    low = b.lower()
    if any(k in low for k in ("explod", "death", "ship", "destruct", "wreck", "combat", "ingame", "fx", "effect", "generic", "essential", "world")):
        print("BANK", b)
