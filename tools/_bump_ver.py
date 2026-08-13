"""Bump the shell / installer / hotfix version in one shot.

Usage: python _bump_ver.py <old> <new> <android_version_code>
"""
import re
import sys

old, new, code = sys.argv[1], sys.argv[2], sys.argv[3]

targets = [
    (r"H:\game_dev\godot_eternal_shell\shell\project.godot",
     [(r'config/version="%s"' % re.escape(old), 'config/version="%s"' % new)]),
    (r"H:\game_dev\godot_eternal_shell\shell\export_presets.cfg",
     [(r"version/code=\d+", "version/code=%s" % code),
      (r'version/name="%s"' % re.escape(old), 'version/name="%s"' % new)]),
    (r"H:\game_dev\godot_eternal_shell\installer\EveAutochess.iss",
     [(r'#define MyAppVersion "%s"' % re.escape(old), '#define MyAppVersion "%s"' % new)]),
    (r"H:\game_dev\eveautochess-dev\tools\pack_hf_content.ps1",
     [(r'\$ver = "%s"' % re.escape(old), '$ver = "%s"' % new)]),
]

for path, subs in targets:
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    for pattern, repl in subs:
        text, n = re.subn(pattern, repl, text, count=1)
        if n != 1:
            raise SystemExit("FAIL %s :: %s" % (path, pattern))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print("OK %s" % path)
