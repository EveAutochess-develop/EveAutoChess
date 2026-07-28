# -*- coding: utf-8 -*-
import csv, io
from pathlib import Path

TA = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache\dgmTypeAttributes.csv")
text = TA.read_bytes().decode("utf-8-sig")
r = csv.DictReader(io.StringIO(text))
fields = r.fieldnames
tidk = fields[0]
aidk = fields[1]
# collect 106 and 352 counts
c106 = c352 = 0
samples106 = []
for row in r:
    aid = int(float(row[aidk]))
    if aid == 106:
        c106 += 1
        if len(samples106) < 15:
            samples106.append((row[tidk], row.get("valueFloat"), row.get("valueInt")))
    elif aid == 352:
        c352 += 1
Path(r"H:\game_dev\eveautochess-dev\tools\_attr106.txt").write_text(
    f"106 count={c106}\n352 count={c352}\nsamples={samples106}\n", encoding="utf-8"
)
print("ok", c106, c352)
