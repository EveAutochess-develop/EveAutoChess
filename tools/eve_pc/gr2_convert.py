# -*- coding: utf-8 -*-
"""Convert EVE PC .gr2 to Wavefront OBJ (requires 64-bit Granny runtime)."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

EVE_PC = Path(__file__).resolve().parent
LEGACY_DIR = EVE_PC / "evegr2toobj_legacy"
LEGACY_EXE = LEGACY_DIR / "evegr2toobj.exe"
LEGACY_DLL = LEGACY_DIR / "granny2.dll"

# User-supplied 64-bit runtime (TriExporter / other licensed copy).
X64_DLL_CANDIDATES = (
    EVE_PC / "granny2_x64.dll",
    EVE_PC / "granny2.dll",
    Path(os.environ.get("GRANNY2_DLL", "")) if os.environ.get("GRANNY2_DLL") else None,
)
X64_EXE_CANDIDATES = (
    EVE_PC / "evegr2toobj_x64.exe",
    EVE_PC / "evegr2tojson.exe",
    Path(os.environ.get("EVEGR2_CONVERTER", "")) if os.environ.get("EVEGR2_CONVERTER") else None,
)


class Gr2ConvertError(RuntimeError):
    pass


def _is_pe64(path: Path) -> bool:
    try:
        import pefile

        pe = pefile.PE(str(path))
        return pe.FILE_HEADER.Machine == 0x8664
    except Exception:
        return False


def _find_x64_toolchain() -> tuple[Path, Path] | None:
    for exe in X64_EXE_CANDIDATES:
        if not exe or not exe.is_file():
            continue
        if not _is_pe64(exe):
            continue
        for dll in X64_DLL_CANDIDATES:
            if dll and dll.is_file() and _is_pe64(dll):
                return exe, dll
    return None


def _gr2_pointer_bits(gr2: Path) -> int:
    try:
        sys_path = EVE_PC / "vendor" / "blendergranny-main" / "io_scene_gr2"
        if str(sys_path) not in __import__("sys").path:
            __import__("sys").path.insert(0, str(sys_path.parent))
            __import__("sys").path.insert(0, str(sys_path))
        from gr2 import read_gr2  # type: ignore

        return int(read_gr2(gr2).header.pointer_size)
    except Exception:
        return 64


def gr2_to_obj(gr2: Path, obj: Path) -> None:
    """Raise Gr2ConvertError when no working 64-bit converter is available."""
    if not gr2.is_file():
        raise Gr2ConvertError(f"missing gr2: {gr2}")
    obj.parent.mkdir(parents=True, exist_ok=True)

    x64 = _find_x64_toolchain()
    if x64:
        exe, dll = x64
        work = exe.parent
        if dll.parent != work:
            # converter expects dll beside exe
            import shutil

            local_dll = work / "granny2.dll"
            if not local_dll.is_file():
                shutil.copy2(dll, local_dll)
        r = subprocess.run(
            [str(exe), str(gr2), str(obj)],
            capture_output=True,
            text=True,
            timeout=180,
            cwd=str(work),
        )
        if r.returncode == 0 and obj.is_file() and obj.stat().st_size > 100:
            return
        err = (r.stderr or r.stdout or "")[-800:]
        raise Gr2ConvertError(f"64-bit converter failed: {err}")

    if LEGACY_EXE.is_file() and LEGACY_DLL.is_file():
        if _gr2_pointer_bits(gr2) == 64:
            raise Gr2ConvertError(
                "EVE Tranquility .gr2 is 64-bit (ptr64); bundled evegr2toobj is 32-bit and will crash. "
                f"Place 64-bit granny2.dll + evegr2toobj_x64.exe in {EVE_PC} "
                "(or set GRANNY2_DLL / EVEGR2_CONVERTER)."
            )
        r = subprocess.run(
            [str(LEGACY_EXE), str(gr2), str(obj)],
            capture_output=True,
            text=True,
            timeout=180,
            cwd=str(LEGACY_DIR),
        )
        if r.returncode == 0 and obj.is_file() and obj.stat().st_size > 100:
            return
        err = (r.stderr or r.stdout or "")[-800:]
        raise Gr2ConvertError(f"32-bit legacy converter failed: {err}")

    raise Gr2ConvertError(
        f"No gr2 converter found. Add 64-bit toolchain under {EVE_PC} "
        "(see gr2_convert.py header)."
    )
