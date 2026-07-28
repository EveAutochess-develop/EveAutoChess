# -*- coding: utf-8 -*-
import csv
import io
from pathlib import Path

OUT = Path(__file__).with_name("_drone_attrs_scan.txt")
ATTRS = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache\dgmAttributeTypes.csv")
TA = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache\dgmTypeAttributes.csv")
lines: list[str] = []

text = ATTRS.read_bytes().decode("utf-8-sig")
r = csv.DictReader(io.StringIO(text))
lines.append("attr cols " + str(r.fieldnames))
idkey = r.fieldnames[0]
namekey = [k for k in r.fieldnames if "ame" in k][0]
drone_ids: set[int] = set()
for row in r:
    name = row[namekey] or ""
    if "drone" in name.lower():
        aid = int(float(row[idkey]))
        drone_ids.add(aid)
        lines.append(f"ATTR {aid} {name}")

text2 = TA.read_bytes().decode("utf-8-sig")
r2 = csv.DictReader(io.StringIO(text2))
lines.append("ta cols " + str(r2.fieldnames))
tidk, aidk = r2.fieldnames[0], r2.fieldnames[1]
want_types = {597, 638, 582, 624, 620}
for row in r2:
    tid = int(float(str(row[tidk]).strip('"')))
    aid = int(float(row[aidk]))
    if tid in want_types and aid in drone_ids:
        lines.append(
            f"TYPE {tid} attr {aid} int={row.get('valueInt')} float={row.get('valueFloat')}"
        )

OUT.write_text("\n".join(lines), encoding="utf-8")
print("wrote", OUT, "lines", len(lines))
