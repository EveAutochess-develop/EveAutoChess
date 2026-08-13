# -*- coding: utf-8 -*-
"""Bake per-pack bow yaw using the rule: the nozzle end IS the stern.

SOF booster positions live in TQ GR2 model space, so:

1. TQ GR2 verts + SOF nozzle positions → stern direction in GR2 space (nozzle
   centroid vs hull centroid). Nozzle *positions* are authoritative; the booster
   transform Z row is only plume length/……, its sign is not a reliable astern cue.
2. GR2 cloud vs pack `model.glb` cloud → the signed axis permutation the GLB
   conversion applied (extent + signed skew per axis).
3. Push the stern direction through that permutation → stern in mesh space →
   `model_yaw_deg` that rotates the stern onto ShipUnit +Z (bow = -Z).

Result is written to the pack's `engine_boosters.json` as `bow_fit`.
"""
from __future__ import annotations

import argparse
import itertools
import json
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from glb_mesh import world_vertices  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
HULLS = ROOT / "tools" / "_extracted" / "sof_hull_boosters.json"

## model_key → (sof_hull, TQ GR2 res path)
TARGETS: dict[str, tuple[str, str]] = {
    "equite": ("afi1_t1", "res:/dx9/model/ship/amarr/fighter/afi1/afi1_t1.gr2"),
    "locust": ("cfi1_t1", "res:/dx9/model/ship/caldari/fighter/cfi1/cfi1_t1.gr2"),
    "satyr": ("gfi1_t1", "res:/dx9/model/ship/gallente/fighter/gfi1/gfi1_t1.gr2"),
    "gram": ("mfi1_t1", "res:/dx9/model/ship/minmatar/fighter/mfi1/mfi1_t1.gr2"),
    "heavy_repair_amarr": ("adh1_t1", "res:/dx9/model/drone/amarr/heavy/adh1/adh1_t1.gr2"),
    "heavy_repair_caldari": ("cdh1_t2", "res:/dx9/model/drone/caldari/heavy/cdh1/cdh1_t2.gr2"),
    "heavy_repair_gallente": ("gdh1_t1", "res:/dx9/model/drone/gallente/heavy/gdh1/gdh1_t1.gr2"),
    "heavy_repair_minmatar": ("mdh1_t1", "res:/dx9/model/drone/minmatar/heavy/mdh1/mdh1_t1.gr2"),
    "wrj_a_shiseng": ("adl1_t1", "res:/dx9/model/drone/amarr/light/adl1/adl1_t1.gr2"),
    "wrj_g_dijingling": ("gdl1_t1", "res:/dx9/model/drone/gallente/light/gdl1/gdl1_t1.gr2"),
    "wrj_j_dahuangfeng": ("cdl1_t1", "res:/dx9/model/drone/caldari/light/cdl1/cdl1_t1.gr2"),
    "wrj_m_mwushi": ("mdl1_t1", "res:/dx9/model/drone/minmatar/light/mdl1/mdl1_t1.gr2"),
    "wrj_ore_excavator": ("oredh2_t1", "res:/dx9/model/drone/ore/heavy/oredh2/oredh2_t1.gr2"),
    ## Freighters: staged length-on-X except cfr1, so the prefix-based TQ bow flip
    ## guesses wrong per hull. Bake the measured yaw instead.
    "tq_freighter_afr1": ("afr1_t1", "res:/dx9/model/ship/amarr/freighter/afr1/afr1_t1.gr2"),
    "tq_freighter_cfr1": ("cfr1_t1", "res:/dx9/model/ship/caldari/freighter/cfr1/cfr1_t1.gr2"),
    "tq_freighter_gfr1": ("gfr1_t1", "res:/dx9/model/ship/gallente/freighter/gfr1/gfr1_t1.gr2"),
    "tq_freighter_mfr1": ("mfr1_t1", "res:/dx9/model/ship/minmatar/freighter/mfr1/mfr1_t1.gr2"),
    ## 2026-08-10 mid-hull multi-cluster trails (Hyperion + logistics BC hulls)
    "glt_haibolongshen": ("gb3_t1", "res:/dx9/model/ship/gallente/battleship/gb3/gb3_t1.gr2"),
    "am_xianquzhe": ("abc2_t1", "res:/dx9/model/ship/amarr/battlecruiser/abc2/abc2_t1.gr2"),
    "jdl_youlong": ("cbc2_t1", "res:/dx9/model/ship/caldari/battlecruiser/cbc2/cbc2_t1.gr2"),
    "glt_bulutikesi": ("gbc1_t1", "res:/dx9/model/ship/gallente/battlecruiser/gbc1/gbc1_t1.gr2"),
    "mmte_baofeng": ("mb2_t1", "res:/dx9/model/ship/minmatar/battleship/mb2/mb2_t1.gr2"),
    ## Pirate / Sansha / Angel titan formation batch (2026-08-13)
    "gsts_duxi": ("cf7_t1", "res:/dx9/model/ship/caldari/frigate/cf7/cf7_t1.gr2"),
    "gsts_qianlong": ("cc2_t1", "res:/dx9/model/ship/caldari/cruiser/cc2/cc2_t1.gr2"),
    "gsts_xiangweishe": ("cb2_t1", "res:/dx9/model/ship/caldari/battleship/cb2/cb2_t1.gr2"),
    "tsl_delamier": ("angf1_t1", "res:/dx9/model/ship/angel/frigate/angf1/angf1_t1.gr2"),
    "tsl_sainabo": ("angbc1_t1", "res:/dx9/model/ship/angel/battlecruiser/angbc1/angbc1_t1.gr2"),
    "tsl_makerui": ("angb1_t1", "res:/dx9/model/ship/angel/battleship/angb1/angb1_t1.gr2"),
    "ts_yemoxia": ("angf2_t1", "res:/dx9/model/ship/angel/frigate/angf2/angf2_t1.gr2"),
    "ts_jingti": ("gc4_t1", "res:/dx9/model/ship/gallente/cruiser/gc4/gc4_t1.gr2"),
    "ts_fuchouzhe": ("gb2_t1", "res:/dx9/model/ship/gallente/battleship/gb2/gb2_t1.gr2"),
    "jmh_asiteluo": ("soef1_t1", "res:/dx9/model/ship/soe/frigate/soef1/soef1_t1.gr2"),
    "jmh_sitexiusi": ("soec1_t1", "res:/dx9/model/ship/soe/cruiser/soec1/soec1_t1.gr2"),
    "jmh_niesituo": ("soeb1_t1", "res:/dx9/model/ship/soe/battleship/soeb1/soeb1_t1.gr2"),
    "xxz_ningxue": ("af8_t1", "res:/dx9/model/ship/amarr/frigate/af8/af8_t1.gr2"),
    "xxz_ashimu": ("ac6_t1", "res:/dx9/model/ship/amarr/cruiser/ac6/ac6_t1.gr2"),
    "xxz_bagelong": ("ab2_t1", "res:/dx9/model/ship/amarr/battleship/ab2/ab2_t1.gr2"),
    "mdt_jiamu": ("morf1_t1", "res:/dx9/model/ship/mordu/frigate/morf1/morf1_t1.gr2"),
    "mdt_aosusi": ("morc1_t1", "res:/dx9/model/ship/mordu/cruiser/morc1/morc1_t1.gr2"),
    "mdt_bagaisi": ("morb1_t1", "res:/dx9/model/ship/mordu/battleship/morb1/morb1_t1.gr2"),
    "ss_monv": ("sf1_t1", "res:/dx9/model/ship/sansha/frigate/sf1/sf1_t1.gr2"),
    "ss_youling": ("sc1_t1", "res:/dx9/model/ship/sansha/cruiser/sc1/sc1_t1.gr2"),
    "ss_emeng": ("sb1_t1", "res:/dx9/model/ship/sansha/battleship/sb1/sb1_t1.gr2"),
    "ss_revenant": ("sca1_t1", "res:/dx9/model/ship/sansha/carrier/sca1/sca1_t1.gr2"),
    "jmh_odysseus": ("soebc1_t1", "res:/dx9/model/ship/soe/battlecruiser/soebc1/soebc1_t1.gr2"),
    "tsl_zhengfuzhe": ("angt1_t1", "res:/dx9/model/ship/angel/titan/angt1/angt1_t1.gr2"),
}


def normalized(cloud: np.ndarray) -> np.ndarray:
    """Centre on the AABB middle and scale to unit longest edge."""
    lo, hi = cloud.min(0), cloud.max(0)
    c = (lo + hi) * 0.5
    scale = float(np.max(hi - lo))
    return (cloud - c) / max(scale, 1e-6)


def signature(cloud: np.ndarray, bins: int = 14) -> np.ndarray:
    """3D occupancy grid — far more discriminative than per-axis marginals,
    and it keeps fore/aft asymmetry so the sign of each axis is decided too."""
    h, _ = np.histogramdd(cloud, bins=(bins, bins, bins), range=((-0.5, 0.5),) * 3)
    h = h.astype(float)
    return h / max(float(h.sum()), 1.0)


def best_axis_map(src: np.ndarray, dst: np.ndarray, stern_src: np.ndarray):
    """Signed permutation matrix taking src cloud onto dst cloud.

    `margin` compares the winner against the best candidate that flips the stern
    to the opposite side — that is the only ambiguity which can mis-orient a hull.
    """
    dst_sig = signature(dst)
    cands = []
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            m = np.zeros((3, 3))
            for dst_ax, src_ax in enumerate(perm):
                m[dst_ax, src_ax] = signs[dst_ax]
            score = float(np.abs(signature(src @ m.T) - dst_sig).sum())
            cands.append((score, m))
    cands.sort(key=lambda t: t[0])
    best_score, best_m = cands[0]
    best_dir = best_m @ stern_src
    opposite = None
    for score, m in cands[1:]:
        if float(np.dot(m @ stern_src, best_dir)) < 0.0:
            opposite = score
            break
    margin = ((opposite - best_score) / max(best_score, 1e-6)) if opposite is not None else 0.0
    return best_m, best_score, margin


def fit(model_key: str, sof_hull: str, res_path: str, hulls: dict, verbose: bool = True):
    pack = PACKS / model_key
    glb = pack / "model.glb"
    ebj = pack / "engine_boosters.json"
    if not glb.is_file() or not ebj.is_file():
        print(f"{model_key:22s} SKIP (missing glb/boosters)")
        return None
    info = hulls.get(sof_hull) or {}
    items = info.get("items") or []
    if not items:
        print(f"{model_key:22s} SKIP (no SOF boosters)")
        return None

    gr2_verts, faces, _uv, _stride, _uvoff = _extract_best(MultiSectionGr2(Path(fetch_resfile(res_path))))
    gr2_verts = np.asarray(gr2_verts, dtype=float)
    used = np.unique(np.asarray(faces).reshape(-1))
    gr2_verts = gr2_verts[used]
    mesh = world_vertices(glb)
    if mesh is None:
        print(f"{model_key:22s} SKIP (empty glb)")
        return None

    ## 1. Stern direction in GR2 space: hull centre → nozzle centroid.
    noz = np.array([[float(v) for v in it["transform"][3][:3]] for it in items], dtype=float)
    lo, hi = gr2_verts.min(0), gr2_verts.max(0)
    hull_c = (lo + hi) * 0.5
    stern_gr2 = noz.mean(0) - hull_c
    stern_gr2 = stern_gr2 / max(float(np.linalg.norm(stern_gr2)), 1e-9)

    ## 2. Signed permutation GR2 → GLB.
    m, score, margin = best_axis_map(normalized(gr2_verts), normalized(mesh), stern_gr2)

    ## 3. Stern in mesh space → yaw that puts it on ShipUnit +Z.
    stern_mesh = m @ stern_gr2
    ## Same rigid map carries the nozzles themselves onto the GLB (uniform scale).
    c_gr2 = (lo + hi) * 0.5
    s_gr2 = max(float(np.max(hi - lo)), 1e-6)
    mlo, mhi = mesh.min(0), mesh.max(0)
    c_mesh = (mlo + mhi) * 0.5
    s_mesh = max(float(np.max(mhi - mlo)), 1e-6)
    noz_mesh = ((noz - c_gr2) * (s_mesh / s_gr2)) @ m.T + c_mesh
    radii = np.array([float(it.get("radius", 0.0) or 0.0) for it in items]) * (s_mesh / s_gr2)
    flat = np.array([stern_mesh[0], 0.0, stern_mesh[2]])
    if float(np.linalg.norm(flat)) < 1e-6:
        print(f"{model_key:22s} SKIP (stern is vertical in mesh space)")
        return None
    flat /= float(np.linalg.norm(flat))
    yaw = math.degrees(math.atan2(-flat[0], flat[2]))
    yaw_snapped = float(round(yaw / 90.0) * 90.0) % 360.0

    ## 4. Normalise nozzles inside the post-yaw mesh AABB, so runtime only needs
    ##    the live ShipUnit-space AABB (scale + recentre are already folded in).
    a = math.radians(yaw_snapped)
    ry = np.array([[math.cos(a), 0.0, math.sin(a)], [0.0, 1.0, 0.0], [-math.sin(a), 0.0, math.cos(a)]])
    mesh_rot = mesh @ ry.T
    noz_rot = noz_mesh @ ry.T
    rlo, rhi = mesh_rot.min(0), mesh_rot.max(0)
    rsize = np.maximum(rhi - rlo, 1e-6)
    noz_norm = (noz_rot - rlo) / rsize
    radii_norm = radii / max(float(rsize.max()), 1e-6)

    out = {
        "sof_hull": sof_hull,
        "gr2": res_path,
        "stern_dir_gr2": [round(float(v), 4) for v in stern_gr2],
        "stern_dir_mesh": [round(float(v), 4) for v in stern_mesh],
        "axis_map": [[int(v) for v in row] for row in m],
        "axis_map_score": round(score, 4),
        "axis_map_margin": round(margin, 4),
        "model_yaw_deg": yaw_snapped,
        "yaw_raw_deg": round(yaw, 1),
        "nozzles_ship_norm": [[round(float(c), 6) for c in p] for p in noz_norm],
        "nozzle_radius_norm": [round(float(r), 6) for r in radii_norm],
        "rule": "nozzle end = stern; yaw rotates stern onto ShipUnit +Z (bow = -Z)",
    }
    if verbose:
        gr2_ext = gr2_verts.max(0) - gr2_verts.min(0)
        gr2_ext = gr2_ext / max(float(gr2_ext.max()), 1e-6)
        mesh_ext = mesh.max(0) - mesh.min(0)
        mesh_ext = mesh_ext / max(float(mesh_ext.max()), 1e-6)
        out["gr2_extent_ratio"] = [round(float(v), 3) for v in gr2_ext]
        out["mesh_extent_ratio"] = [round(float(v), 3) for v in mesh_ext]
        print(
            f"{model_key:22s} stern_gr2={np.round(stern_gr2, 2)} -> mesh={np.round(stern_mesh, 2)} "
            f"yaw={yaw_snapped:6.1f} score={score:.3f} margin={margin:.2f} "
            f"gr2_ext={np.round(gr2_ext, 2)} mesh_ext={np.round(mesh_ext, 2)}"
        )
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--only", nargs="*", default=None)
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    hulls = json.loads(HULLS.read_text(encoding="utf-8"))
    keys = args.only or list(TARGETS)
    written = 0
    for key in keys:
        if key not in TARGETS:
            print(f"{key}: no GR2 mapping")
            continue
        sof_hull, res_path = TARGETS[key]
        r = fit(key, sof_hull, res_path, hulls)
        if r is None or not args.write:
            continue
        ebj = PACKS / key / "engine_boosters.json"
        doc = json.loads(ebj.read_text(encoding="utf-8"))
        doc["bow_fit"] = r
        ebj.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        written += 1
    print(f"written={written}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
