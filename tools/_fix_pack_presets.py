# -*- coding: utf-8 -*-
from pathlib import Path
import re

p = Path(r"H:/game_dev/eveautochess-dev/godot_project/export_presets.cfg")
text = p.read_text(encoding="utf-8")


def fix_preset(m: re.Match) -> str:
	block = m.group(0)
	block = block.replace('export_filter="resources"', 'export_filter="all_resources"')
	block = re.sub(r"export_files=PackedStringArray\(\)\r?\n", "", block)
	block = re.sub(
		r'(name="Pack[^"]+"\r?\n)',
		r"\1export_files=PackedStringArray()\n",
		block,
		count=1,
	)
	return block


text2 = re.sub(r"\[preset\.[2-5]\][\s\S]*?(?=\[preset\.|\Z)", fix_preset, text)
p.write_text(text2, encoding="utf-8")
for i, line in enumerate(text2.splitlines(), 1):
	if 73 <= i <= 190 and line.strip():
		print(f"{i}:{line}")
