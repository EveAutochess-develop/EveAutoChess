# -*- coding: utf-8 -*-
"""Try ooz BitKnit2 DLL on aca2/mca2 section 0; export mesh if full."""
from __future__ import annotations

import ctypes
import json
import shutil
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from bake_pc_textures import bake_bundle_for_res_path  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from io_scene_gr2.gr2.file import read_gr2  # noqa: E402
from io_scene_gr2.gr2.fixup import load_sections  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best, write_obj  # noqa: E402
from stage_mining_threeviews import auto_orient  # noqa: E402

DLL = ROOT / "tools" / "eve_pc" / "vendor" / "ooz" / "ooz_bitknit2.dll"
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
REVIEW = Path(r"H:\game_dev\cg-director-studio\projects\eveautochess-opening\_review\supercarrier_cg")

TARGETS = [
    {
        "key": "tq_supercarrier_a",
        "en": "Aeon",
        "zh": "永恒级",
        "race": "A",
        "gr2": "res:/dx9/model/ship/amarr/carrier/aca2/aca2_t1_lowdetail.gr2",
        "bake": "res:/dx9/model/ship/amarr/carrier/aca2/aca2_t1.gr2",
        "alts": [
            "res:/dx9/model/ship/amarr/carrier/aca2/aca2_t1.gr2",
            "res:/dx9/model/ship/amarr/carrier/aca2/aca2_t2_lowdetail.gr2",
        ],
    },
    {
        "key": "tq_supercarrier_m",
        "en": "Hel",
        "zh": "地狱级",
        "race": "M",
        "gr2": "res:/dx9/model/ship/minmatar/carrier/mca2/mca2_t1_lowdetail.gr2",
        "bake": "res:/dx9/model/ship/minmatar/carrier/mca2/mca2_t1.gr2",
        "alts": [
            "res:/dx9/model/ship/minmatar/carrier/mca2/mca2_t1.gr2",
            "res:/dx9/model/ship/minmatar/carrier/mca2/mca2_t2_lowdetail.gr2",
        ],
    },
]


class OozBackend:
    def __init__(self, dll: ctypes.CDLL):
        self.dll = dll
        self.dll.ooz_bitknit2_decompress.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_int),
        ]
        self.dll.ooz_bitknit2_decompress.restype = ctypes.c_int
        self.valid_len: dict[int, int] = {}

    def decompress(self, section, compressed: bytes) -> bytes:
        from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
        from io_scene_gr2.gr2.decompress import decompress_section, DecompressionError

        if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
            out = decompress_section(section, compressed)
            self.valid_len[section.index] = len(out)
            return out
        if not compressed:
            self.valid_len[section.index] = 0
            return b""
        dst = (ctypes.c_ubyte * section.expanded_size)()
        written = ctypes.c_int(0)
        src_buf = (ctypes.c_ubyte * len(compressed)).from_buffer_copy(compressed)
        rc = self.dll.ooz_bitknit2_decompress(
            src_buf, len(compressed), dst, section.expanded_size, ctypes.byref(written)
        )
        out = bytes(dst[: max(written.value, 0)])
        print(
            f"    ooz s{section.index} rc={rc} written={written.value}/{section.expanded_size} "
            f"comp={len(compressed)}"
        )
        if written.value < section.expanded_size:
            # pad so fixups can apply; refuse reads past valid_len in MultiSectionGr2
            self.valid_len[section.index] = written.value
            return out + bytes(section.expanded_size - written.value)
        self.valid_len[section.index] = written.value
        return out


def try_export(t: dict, dll: ctypes.CDLL) -> dict:
    paths = [t["gr2"], *t.get("alts", [])]
    last = ""
    for res in paths:
        try:
            print(f"[try] {t['key']} {t['en']} <- {res}")
            path = Path(fetch_resfile(res))
            gr2 = read_gr2(path)
            for s in gr2.sections:
                print(
                    f"  s{s.index} {s.compression_name} comp={len(gr2.section_bytes(s))} "
                    f"exp={s.expanded_size}"
                )
            backend = OozBackend(dll)

            # Monkey-patch MultiSectionGr2 loading by using load_sections directly
            class G(MultiSectionGr2):
                def __init__(self, p: Path):
                    g = read_gr2(p)
                    self.loaded = load_sections(g, backend)
                    self._valid_len = backend.valid_len
                    self._fixups = {
                        (f.source_section, f.source_offset): f.target
                        for f in self.loaded.pointer_fixups
                    }
                    self.nsec = len(self.loaded.sections_fixed)
                    self.ptr_size = g.header.pointer_size // 8
                    from reexport_titan_glb_with_uv import LAYOUT_32, LAYOUT_64

                    self.layout = LAYOUT_64 if self.ptr_size == 8 else LAYOUT_32

            g = G(path)
            verts, faces, uvs, stride, uv_off = _extract_best(g)
            verts = auto_orient(verts, faces)
            if uv_off < 0:
                uvs = np.zeros((len(verts), 2), dtype=np.float32)
            out = PACKS / t["key"]
            out.mkdir(parents=True, exist_ok=True)
            obj = out / "_tmp.obj"
            write_obj(verts, faces, uvs, obj)
            glb = out / "model.glb"
            assimp_convert(obj, glb, "glb2")
            obj.unlink(missing_ok=True)
            try:
                bake_bundle_for_res_path(t["key"], t["bake"])
            except Exception as e:  # noqa: BLE001
                print("  bake warn:", e)
            dst = REVIEW / t["race"]
            dst.mkdir(parents=True, exist_ok=True)
            shutil.copy2(glb, dst / "model.glb")
            meta = {
                "key": t["key"],
                "en": t["en"],
                "zh": t["zh"],
                "race": t["race"],
                "status": "ok",
                "res": res,
                "stride": stride,
                "uv_off": uv_off,
                "verts": int(len(verts)),
                "tris": int(len(faces)),
                "decoder": "ooz_bitknit2",
                "valid_len": dict(backend.valid_len),
            }
            (out / "bundle_meta.json").write_text(
                json.dumps({**meta, "model_long_axis": 1400.0}, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            return meta
        except Exception as e:  # noqa: BLE001
            last = str(e)
            print(f"  fail: {e}")
    return {"key": t["key"], "en": t["en"], "status": "fail", "error": last}


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    dll = ctypes.CDLL(str(DLL))
    reports = [try_export(t, dll) for t in TARGETS]
    # merge into existing review json
    prev_path = REVIEW / "ingame_bundles.json"
    prev = json.loads(prev_path.read_text(encoding="utf-8")) if prev_path.is_file() else []
    by_key = {r["key"]: r for r in prev}
    for r in reports:
        old = by_key.get(r["key"], {})
        if "textures" in old and "textures" not in r:
            r["textures"] = old["textures"]
        by_key[r["key"]] = r
    # keep C/G
    order = ["tq_supercarrier_a", "tq_supercarrier_c", "tq_supercarrier_g", "tq_supercarrier_m"]
    out = [by_key[k] for k in order if k in by_key]
    prev_path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    for r in reports:
        print("RESULT", r.get("status"), r.get("key"), r.get("tris") or r.get("error"))


if __name__ == "__main__":
    main()
