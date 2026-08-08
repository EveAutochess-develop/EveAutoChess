# -*- coding: utf-8 -*-
"""Clean-uninstall Eve Autochess on Windows (local or via SSH)."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

APP_NAMES = ("EveAutochess", "EVE自走棋")


def run(cmd: list[str]) -> int:
    print("+", " ".join(cmd))
    return subprocess.call(cmd, shell=False)


def kill_game() -> None:
    run(["taskkill", "/F", "/IM", "EveAutochess.exe", "/T"])


def uninstall_via_registry() -> None:
    import winreg

    roots = [
        (winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_LOCAL_MACHINE, r"Software\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_LOCAL_MACHINE, r"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
    ]
    for root, path in roots:
        try:
            key = winreg.OpenKey(root, path)
        except OSError:
            continue
        i = 0
        while True:
            try:
                sub = winreg.EnumKey(key, i)
            except OSError:
                break
            i += 1
            try:
                sk = winreg.OpenKey(key, sub)
                display, _ = winreg.QueryValueEx(sk, "DisplayName")
                uninst, _ = winreg.QueryValueEx(sk, "UninstallString")
            except OSError:
                continue
            disp = str(display)
            if not any(n in disp for n in APP_NAMES) and "EveAutochess" not in disp:
                continue
            print("Found uninstall:", disp, "->", uninst)
            # Prefer quiet Inno
            cmd = uninst
            if "unins" in uninst.lower():
                if "/SILENT" not in uninst.upper():
                    cmd = f'{uninst} /SILENT /NORESTART'
            run(["cmd", "/c", cmd])


def wipe_dirs() -> None:
    local = Path(os.environ.get("LOCALAPPDATA", ""))
    roaming = Path(os.environ.get("APPDATA", ""))
    candidates = [
        local / "Programs" / "EveAutochess",
        local / "EveAutochess",
        roaming / "EveAutochess",
        roaming / "Godot" / "app_userdata" / "EVE自走棋",
        roaming / "Godot" / "app_userdata" / "EVE???",
    ]
    for d in candidates:
        if d.exists():
            print("DelTree", d)
            shutil.rmtree(d, ignore_errors=True)
    # Desktop / Start Menu shortcuts
    for base in (Path(os.environ.get("USERPROFILE", "")) / "Desktop",
                 Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs"):
        for name in ("EVE自走棋.lnk", "EveAutochess.lnk"):
            p = base / name
            if p.exists():
                print("Delete", p)
                p.unlink(missing_ok=True)


def main() -> int:
    print("=== Eve Autochess clean uninstall ===")
    kill_game()
    try:
        uninstall_via_registry()
    except Exception as e:
        print("registry uninstall error:", e)
    wipe_dirs()
    print("=== done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
