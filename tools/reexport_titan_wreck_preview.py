# -*- coding: utf-8 -*-
"""Re-export titan WRECK GLBs for kill preview with UV when available.

Uses MultiSectionGr2, which selects Granny field offsets from the GR2 pointer
size: G/M wrecks are 64-bit, A/C wrecks are 32-bit + BitKnit2.
Does NOT touch intact hull packs / doomsday preview.
"""
from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
DESIGN = Path(r"H:\game_dev\eveautochess-design")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from eve_pc.dds_decode import save_png  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best, write_obj  # noqa: E402
from stage_mining_threeviews import auto_orient  # noqa: E402

OUT = DESIGN / "docs" / "_review" / "20260731_confirm" / "titan_kill_preview"
GODOT = ROOT / "godot_project"
WRECK_GLB = GODOT / "assets" / "models" / "preview" / "titans" / "wreck"
TEX = WRECK_GLB / "tex"

# auto_orient picks the bow by cross-section taper, which is unreliable on broken
# wreck meshes, so the length axis is calibrated per race against the intact hull
# shown in the kill preview (flip_length=True means reverse X after auto_orient).
# Confirmed in-preview via the bow markers: only A matches auto_orient's guess.
TITANS = [
    {
        "race": "A",
        "key": "tq_titan_wreck_a",
        "hull": "at1",
        "flip_length": False,
        "gr2": [
            "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck_lowdetail.gr2",
            "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck.gr2",
        ],
        "albedo": "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck_o_lowdetail.dds",
        "glow": "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck_g_lowdetail.dds",
    },
    {
        "race": "C",
        "key": "tq_titan_wreck_c",
        "hull": "ct1",
        "flip_length": False,
        "gr2": [
            "res:/dx9/model/ship/caldari/titan/ct1/wreck/ct1_t1_wreck_lowdetail.gr2",
            "res:/dx9/model/ship/caldari/titan/ct1/wreck/ct1_t1_wreck.gr2",
        ],
        "albedo": "res:/dx9/model/ship/caldari/titan/ct1/wreck/ct1_t1_wreck_o_lowdetail.dds",
        "glow": "res:/dx9/model/ship/caldari/titan/ct1/wreck/ct1_t1_wreck_g_lowdetail.dds",
    },
    {
        "race": "G",
        "key": "tq_titan_wreck_g",
        "hull": "gt1",
        "flip_length": True,
        "gr2": [
            "res:/dx9/model/ship/gallente/titan/gt1/wreck/gt1_t1_wreck.gr2",
            "res:/dx9/model/ship/gallente/titan/gt1/wreck/gt1_t1_wreck_lowdetail.gr2",
        ],
        "albedo": "res:/dx9/model/ship/gallente/titan/gt1/wreck/gt1_t1_wreck_o_lowdetail.dds",
        "glow": "res:/dx9/model/ship/gallente/titan/gt1/wreck/gt1_t1_wreck_g_lowdetail.dds",
    },
    {
        "race": "M",
        "key": "tq_titan_wreck_m",
        "hull": "mt1",
        "flip_length": False,
        "gr2": [
            "res:/dx9/model/ship/minmatar/titan/mt1/wreck/mt1_t1_wreck_lowdetail.gr2",
            "res:/dx9/model/ship/minmatar/titan/mt1/wreck/mt1_t1_wreck.gr2",
        ],
        "albedo": "res:/dx9/model/ship/minmatar/titan/mt1/wreck/mt1_t1_wreck_o_lowdetail.dds",
        "glow": "res:/dx9/model/ship/minmatar/titan/mt1/wreck/mt1_t1_wreck_g_lowdetail.dds",
    },
    {
        "race": "Angel",
        "key": "tsl_zhengfuzhe_wreck",
        "hull": "angt1",
        "hull_key": "tsl_zhengfuzhe",
        "hull_gr2": "res:/dx9/model/ship/angel/titan/angt1/angt1_t1.gr2",
        "flip_length": False,
        "gr2": [
            "res:/dx9/model/ship/angel/titan/angt1/wreck/angt1_t1_wreck_lowdetail.gr2",
            "res:/dx9/model/ship/angel/titan/angt1/wreck/angt1_t1_wreck.gr2",
        ],
        "albedo": "res:/dx9/model/ship/angel/titan/angt1/wreck/angt1_t1_wreck_o_lowdetail.dds",
        "glow": "res:/dx9/model/ship/angel/titan/angt1/wreck/angt1_t1_wreck_g_lowdetail.dds",
    },
]


def _hull_key(t: dict) -> str:
    return str(t.get("hull_key") or f"tq_titan_{t['race'].lower()}")


def export_tex(t: dict) -> dict:
    """Wreck-specific *_o DDS are tiny overlay stubs (~1KB), not usable albedo.

    First pass: copy the intact hull §0 maps (albedo/normal/pmwo/rg/reduction)
    so ShipUnit takes the same Unity shader path as the live ship. Keep raw
    wreck_o/g only in the review folder for later tuning.
    """
    TEX.mkdir(parents=True, exist_ok=True)
    review = OUT / "wrecks" / t["race"]
    review.mkdir(parents=True, exist_ok=True)
    out: dict = {"source": "hull_§0"}
    for kind, res in (("o", t["albedo"]), ("g", t.get("glow"))):
        if not res:
            continue
        try:
            src = Path(fetch_resfile(res))
            dst = TEX / f"{t['race']}_{kind}.png"
            if save_png(src, dst, max_dim=2048):
                shutil.copy2(dst, review / dst.name)
                out[f"wreck_{kind}"] = str(dst.relative_to(GODOT)).replace("\\", "/")
                out[f"wreck_{kind}_bytes"] = src.stat().st_size
        except Exception as e:
            out[f"wreck_{kind}_err"] = str(e)

    hull_dir = GODOT / "assets" / "models" / "ships" / _hull_key(t)
    bundle = GODOT / "assets" / "models" / "ships" / t["key"]
    bundle.mkdir(parents=True, exist_ok=True)
    copied = []
    for name in ("albedo.png", "normal.png", "pmwo.png", "rg.png", "reduction.png"):
        src = hull_dir / name
        if not src.is_file():
            out[f"missing_{name}"] = str(src)
            continue
        shutil.copy2(src, bundle / name)
        shutil.copy2(src, review / f"hull_{name}")
        copied.append(name)
    out["copied_from_hull"] = copied
    out["hull_key"] = _hull_key(t)
    return out


def _center_scale(pts: np.ndarray, faces: np.ndarray | None = None) -> np.ndarray:
    idx = np.unique(faces.reshape(-1)) if faces is not None else np.arange(len(pts))
    mn, mx = pts[idx].min(0), pts[idx].max(0)
    ext = float(np.max(mx - mn))
    if ext < 1e-6:
        return pts.copy()
    return (pts - (mn + mx) * 0.5) * (8.0 / ext)


def _grid_nn_uv(src_pos: np.ndarray, src_uv: np.ndarray, dst_pos: np.ndarray) -> np.ndarray:
    cell = 8.0 / 40.0
    buckets: dict[tuple[int, int, int], list[int]] = {}
    qi = np.floor(src_pos / cell).astype(np.int32)
    for i in range(len(src_pos)):
        buckets.setdefault((int(qi[i, 0]), int(qi[i, 1]), int(qi[i, 2])), []).append(i)
    out = np.zeros((len(dst_pos), 2), dtype=np.float64)
    di = np.floor(dst_pos / cell).astype(np.int32)
    for j in range(len(dst_pos)):
        x, y, z = int(di[j, 0]), int(di[j, 1]), int(di[j, 2])
        best = 1e18
        buv = src_uv[0]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    ids = buckets.get((x + dx, y + dy, z + dz))
                    if not ids:
                        continue
                    d = src_pos[ids] - dst_pos[j]
                    d2 = np.einsum("ij,ij->i", d, d)
                    k = int(np.argmin(d2))
                    if d2[k] < best:
                        best = float(d2[k])
                        buv = src_uv[ids[k]]
        out[j] = buv
    return out


def _uv_collapsed(uvs: np.ndarray, faces: np.ndarray) -> bool:
    used = np.unique(faces.reshape(-1))
    sample = uvs[used]
    med = np.median(sample, axis=0)
    return bool(np.min(np.abs(med - 1.0)) < 0.08 or np.max(np.abs(med)) < 0.05)


def transfer_uv_from_hull_gr2(wreck_verts: np.ndarray, wreck_faces: np.ndarray, hull_res: str) -> np.ndarray:
    """Copy intact-hull UVs in native GR2 space (same SOF hull), then caller orients the mesh."""
    print(f"  UV collapsed → NN from hull GR2 {hull_res}")
    hg = MultiSectionGr2(Path(fetch_resfile(hull_res)))
    hverts, hfaces, huvs, hstride, huv_off = _extract_best(hg)
    print(f"  hull verts={len(hverts)} uv_off={huv_off} stride={hstride}")
    hpos = _center_scale(hverts, hfaces)
    wpos = _center_scale(wreck_verts, wreck_faces)
    return _grid_nn_uv(hpos, huvs, wpos)


def export_mesh(t: dict) -> dict:
    WRECK_GLB.mkdir(parents=True, exist_ok=True)
    review = OUT / "wrecks" / t["race"]
    review.mkdir(parents=True, exist_ok=True)
    last = ""
    for res in t["gr2"]:
        try:
            print(f"[wreck] {t['race']} <- {res}")
            g = MultiSectionGr2(Path(fetch_resfile(res)))
            verts, faces, uvs, stride, uv_off = _extract_best(g)
            uv_src = "gr2"
            hull_gr2 = str(t.get("hull_gr2") or "")
            if hull_gr2 and (uvs is None or _uv_collapsed(uvs, faces)):
                uvs = transfer_uv_from_hull_gr2(verts, faces, hull_gr2)
                uv_src = "hull_gr2_nn"
                uv_off = 16
            verts = auto_orient(verts, faces)
            if t.get("flip_length", False):
                verts = verts.copy()
                verts[:, 0] *= -1.0
            # Center/scale from vertices the kept faces actually reference: stray
            # unreferenced verts otherwise skew the bbox and offset the wreck.
            used = np.unique(faces.reshape(-1))
            mins, maxs = verts[used].min(0), verts[used].max(0)
            extent = float(np.max(maxs - mins))
            if extent > 1e-6:
                verts = (verts - (mins + maxs) * 0.5) * (8.0 / extent)
            obj = review / f"{t['hull']}_wreck_uv.obj"
            write_obj(verts, faces, uvs, obj)
            glb = WRECK_GLB / f"{t['hull']}.glb"
            assimp_convert(obj, glb, "glb2")
            shutil.copy2(glb, review / f"{t['hull']}.glb")
            bundle = GODOT / "assets" / "models" / "ships" / t["key"]
            bundle.mkdir(parents=True, exist_ok=True)
            shutil.copy2(glb, bundle / "model.glb")
            (bundle / "textures_pc.txt").write_text(
                "\n".join(
                    [
                        f"gr2={res}",
                        f"albedo_src=hull:{_hull_key(t)}/albedo.png  (wreck_o DDS is stub overlay, not used for tint)",
                        f"maps=copied from assets/models/ships/{_hull_key(t)} §0",
                        f"uv_src={uv_src}",
                        "channel=DataStore.resolve_model_bundle -> ShipUnit._tint_model -> ShipLook",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            obj.unlink(missing_ok=True)
            # Confirm GLB attrs
            data = glb.read_bytes()
            jlen = struct.unpack_from("<I", data, 12)[0]
            j = json.loads(data[20 : 20 + jlen])
            attrs = []
            for m in j.get("meshes", []):
                for pr in m.get("primitives", []):
                    attrs.append(sorted(pr.get("attributes", {}).keys()))
            return {
                "race": t["race"],
                "status": "ok",
                "res": res,
                "stride": stride,
                "uv_off": uv_off,
                "has_uv": uv_off >= 0,
                "uv_src": uv_src,
                "verts": int(len(verts)),
                "tris": int(len(faces)),
                "glb": str(glb.relative_to(GODOT)).replace("\\", "/"),
                "glb_attrs": attrs,
                "anims": 0,
            }
        except Exception as e:
            last = str(e)
            print(f"  fail: {e}")
    return {"race": t["race"], "status": "fail", "error": last, "anims": 0}


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass
    only = ""
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].strip().lower()
        elif a == "--only" and len(sys.argv) > sys.argv.index(a) + 1:
            only = str(sys.argv[sys.argv.index(a) + 1]).strip().lower()
    only_set = {p.strip() for p in only.split(",") if p.strip()} if only else set()
    reports = []
    titans = [t for t in TITANS if (not only_set or str(t["race"]).lower() in only_set)]
    if only_set and not titans:
        raise SystemExit(f"no titan matching --only={only}")
    for t in titans:
        tex = export_tex(t)
        mesh = export_mesh(t)
        mesh["tex"] = tex
        reports.append(mesh)
        print(mesh)
    OUT.mkdir(parents=True, exist_ok=True)
    report_path = OUT / "wreck_uv_export_report.json"
    if only_set and report_path.is_file():
        try:
            prev = json.loads(report_path.read_text(encoding="utf-8"))
            if isinstance(prev, list):
                by_race = {str(r.get("race")): r for r in prev if isinstance(r, dict)}
                for r in reports:
                    by_race[str(r.get("race"))] = r
                reports = list(by_race.values())
        except Exception:
            pass
    report_path.write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [
        "# Titan wreck re-export (UV)",
        "",
        "## Client paths (TQ)",
        "",
        "| Race | wreck GR2 | albedo DDS |",
        "|---|---|---|",
    ]
    for t in TITANS:
        lines.append(f"| {t['race']} | `{t['gr2'][0]}` | `{t['albedo']}` |")
    lines += [
        "",
        "## Animations",
        "",
        "Wreck GR2 `Animations` / `TrackGroups` count = **0** (G/M/A/C/Angel lowdetail inspected).",
        "Client wreck ambience is particle (`*_wreck_cloud.black` + `wreckfire_generic_*`), not skeletal mesh anim.",
        "Current preview GLBs: **no `animations` / `skins`** → nothing to play.",
        "",
        "## Export status",
        "",
    ]
    for r in reports:
        lines.append(
            f"- {r['race']}: `{r.get('status')}` uv={r.get('has_uv')} "
            f"{r.get('glb', r.get('error', ''))}"
        )
    (OUT / "WRECK_UV_NOTES.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    ok = sum(1 for r in reports if r.get("status") == "ok")
    print(f"done ok={ok}/{len(reports)}")


if __name__ == "__main__":
    main()
