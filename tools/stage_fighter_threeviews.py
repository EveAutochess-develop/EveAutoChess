# -*- coding: utf-8 -*-
"""Stage fighter orthographic three-views from PC GR2 (correct Meshes parse).

EVE Tranquility fighter GR2 root type is truncated to ArtToolInfo only.
Walk FileInfo object with packed AOR layout (int32 count + int64 ptr = 12 bytes),
read Meshes → PrimaryVertexData (float3 Position) + TriTopology.Indices16.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from io_scene_gr2.gr2.file import read_gr2  # noqa: E402
from io_scene_gr2.gr2.fixup import load_sections  # noqa: E402

OUT = Path(r"H:\game_dev\eveautochess-design\docs\_review\capital_cyno_assets_confirm")
SIZE = 512

FIGHTERS = [
    ("17_骑士_Equite", "骑士", "Equite I", "res:/dx9/model/ship/amarr/fighter/afi1/afi1_t1.gr2"),
    ("18_蚂蚱_Locust", "蚂蚱", "Locust I", "res:/dx9/model/ship/caldari/fighter/cfi1/cfi1_t1.gr2"),
    ("19_萨梯_Satyr", "萨梯", "Satyr I", "res:/dx9/model/ship/gallente/fighter/gfi1/gfi1_t1.gr2"),
    ("20_拉格墨_Gram", "拉格墨", "Gram I", "res:/dx9/model/ship/minmatar/fighter/mfi1/mfi1_t1.gr2"),
]


class Gr2Meshes:
    def __init__(self, path: Path):
        self.loaded = load_sections(read_gr2(path))
        self.data = self.loaded.sections_fixed[0]

    def res(self, v: int):
        return self.loaded.resolve_fake_pointer(v)

    def u32(self, off: int) -> int:
        return struct.unpack_from("<I", self.data, off)[0]

    def u64(self, off: int) -> int:
        return struct.unpack_from("<Q", self.data, off)[0]

    def cstr(self, off: int) -> str:
        end = self.data.find(b"\x00", off)
        return self.data[off:end].decode("ascii", "replace")

    def aor(self, off: int) -> tuple[int, object | None]:
        """Packed array-of-references: int32 count + int64 ptr (12 bytes)."""
        count = self.u32(off)
        ptr = self.res(self.u64(off + 4))
        return count, ptr

    def mesh_list(self) -> list[tuple[str, int]]:
        # FileInfo @0: ArtTool(8)+Exporter(8)+FromFile(8)=24, then AORs ×12
        # Textures@24 Materials@36 Skeletons@48 VertexDatas@60 TriTopologies@72 Meshes@84
        count, arr = self.aor(84)
        if not arr or count <= 0:
            raise RuntimeError(f"no meshes (count={count})")
        out = []
        for i in range(count):
            mref = self.res(self.u64(arr.offset + i * 8))
            if not mref:
                continue
            nref = self.res(self.u64(mref.offset))
            name = self.cstr(nref.offset) if nref else f"mesh_{i}"
            out.append((name, mref.offset))
        return out

    def extract_mesh(self, mesh_off: int) -> tuple[np.ndarray, np.ndarray]:
        # Mesh: Name@0, PVD@8, Morph AOR@16 (12), PrimaryTopology@28
        pvd = self.res(self.u64(mesh_off + 8))
        topo = self.res(self.u64(mesh_off + 28))
        if not pvd or not topo:
            raise RuntimeError("missing PVD/topology")

        # VertexData: Type@0, Vertices AOR@8 (count + ptr packed in 12)
        vcount, varr = self.aor(pvd.offset + 8)
        if not varr or vcount < 3:
            raise RuntimeError(f"bad vertex array count={vcount}")

        # TriTopology: Groups AOR@0, Indices32 AOR@12, Indices16 AOR@24
        i16_count, i16_arr = self.aor(topo.offset + 24)
        if not i16_arr or i16_count < 3:
            i32_count, i32_arr = self.aor(topo.offset + 12)
            if not i32_arr or i32_count < 3:
                raise RuntimeError("no indices")
            idx = np.frombuffer(
                self.data[i32_arr.offset : i32_arr.offset + i32_count * 4], dtype="<u4"
            ).astype(np.int32)
        else:
            idx = np.frombuffer(
                self.data[i16_arr.offset : i16_arr.offset + i16_count * 2], dtype="<u2"
            ).astype(np.int32)

        usable = len(idx) - (len(idx) % 3)
        faces_all = idx[:usable].reshape(-1, 3)
        faces_all = faces_all[(faces_all < vcount).all(axis=1)]

        # EVE fighters: often Pos(12)+extra (stride 20) or Pos+Normal (24).
        # Declared granny type is often truncated; probe by median edge length.
        best: tuple[float, int, np.ndarray, np.ndarray, int] | None = None
        for stride in (20, 24, 28, 32, 16, 12, 36, 40, 48):
            if stride % 4 != 0:
                continue
            need = vcount * stride
            if varr.offset + need > len(self.data):
                continue
            blob = self.data[varr.offset : varr.offset + need]
            arr = np.frombuffer(blob, dtype="<f4")
            fpp = stride // 4
            verts = arr.reshape(-1, fpp)[:vcount, :3].astype(np.float64)
            if not np.isfinite(verts).all():
                continue
            faces = faces_all
            mag = np.linalg.norm(verts, axis=1)
            sane = mag < 1e5
            if int(sane.sum()) < 32:
                continue
            p50 = float(np.median(mag[sane]))
            keep = mag <= max(p50 * 8.0, 50.0)
            faces = faces[keep[faces].all(axis=1)]
            if len(faces) < 32:
                continue
            e1 = np.linalg.norm(verts[faces[:, 0]] - verts[faces[:, 1]], axis=1)
            e2 = np.linalg.norm(verts[faces[:, 1]] - verts[faces[:, 2]], axis=1)
            e3 = np.linalg.norm(verts[faces[:, 2]] - verts[faces[:, 0]], axis=1)
            emax = np.maximum(np.maximum(e1, e2), e3)
            med = float(np.median(emax))
            # Prefer compact, manifold-like meshes (fighters ~0.1–1.0)
            if med < 1e-4 or med > 50.0:
                continue
            faces = faces[emax <= med * 6.0]
            if len(faces) < 32:
                continue
            # Prefer lower median edge; break ties by more faces
            score = (med, -len(faces))
            if best is None or score < (best[0], -best[1]):
                best = (med, len(faces), verts, faces, stride)
        if best is None:
            raise RuntimeError("no usable stride")
        med, nfaces, verts, faces, stride = best
        print(f"    stride={stride} edge_med={med:.3f} tris={nfaces}")
        return verts, faces


def pick_best_mesh(g: Gr2Meshes) -> tuple[str, np.ndarray, np.ndarray]:
    meshes = g.mesh_list()
    ranked = []
    for name, off in meshes:
        try:
            verts, faces = g.extract_mesh(off)
            used = np.unique(faces.reshape(-1))
            ext = np.ptp(verts[used], axis=0)
            score = (0 if "LOD" in name.upper() else 1, len(faces), float(ext.max()))
            ranked.append((score, name, verts, faces))
            print(f"  mesh {name!r}: verts={len(verts)} tris={len(faces)} ext={ext}")
        except Exception as e:
            print(f"  mesh {name!r}: FAIL {e}")
    if not ranked:
        raise RuntimeError("no usable mesh")
    ranked.sort(key=lambda t: t[0], reverse=True)
    _s, name, verts, faces = ranked[0]
    return name, verts, faces


def auto_orient(verts: np.ndarray, faces: np.ndarray) -> np.ndarray:
    """Remap to X=length, Y=up, Z=beam; nose toward -X.

    Prefer original Y as up. Beam = horizontal axis with stronger left/right
    symmetry in the front projection (wingspan); length = the other horizontal.
    """
    used = np.unique(faces.reshape(-1))
    ext = np.ptp(verts[used], axis=0)
    up_ax = 1 if int(np.argmax(ext)) != 1 else int(np.argmin(ext))
    horiz = [i for i in range(3) if i != up_ax]

    def front_symmetry(beam_ax: int) -> float:
        pts = verts[used][:, [beam_ax, up_ax]].astype(np.float64).copy()
        pts -= pts.mean(axis=0)
        # 2D density overlap with mirror across beam=0
        h, _, _ = np.histogram2d(pts[:, 0], pts[:, 1], bins=40)
        h = h / (h.sum() + 1e-9)
        return float(np.minimum(h, np.flipud(h)).sum())

    s0 = front_symmetry(horiz[0])
    s1 = front_symmetry(horiz[1])
    if s0 >= s1:
        beam_ax, length_ax = horiz[0], horiz[1]
        sym = s0
    else:
        beam_ax, length_ax = horiz[1], horiz[0]
        sym = s1

    m = np.zeros((3, 3), dtype=np.float64)
    m[0, length_ax] = 1.0
    m[1, up_ax] = 1.0
    m[2, beam_ax] = 1.0
    v = verts @ m.T
    mid = float(v[used, 0].mean())
    hi = used[v[used, 0] > mid]
    lo = used[v[used, 0] <= mid]

    def yz_span(idx: np.ndarray) -> float:
        if len(idx) < 8:
            return 1e9
        return float(np.ptp(v[idx][:, 1:3], axis=0).sum())

    if yz_span(hi) < yz_span(lo):
        v = v.copy()
        v[:, 0] *= -1.0
    print(
        f"    orient length={length_ax} up={up_ax} beam={beam_ax} "
        f"ext={ext} sym={sym:.3f}"
    )
    return v


def render_ortho(verts: np.ndarray, faces: np.ndarray, view: str, size: int = SIZE) -> Image.Image:
    # Canonical: X forward/aft, Y up, Z beam
    used = np.unique(faces.reshape(-1))
    center = verts[used].mean(axis=0)
    vv = verts - center
    if view == "front":
        xy = vv[:, [2, 1]]
        depth = -vv[:, 0]
    elif view == "side":
        xy = vv[:, [0, 1]]
        depth = vv[:, 2]
    else:
        xy = vv[:, [0, 2]]
        depth = -vv[:, 1]

    ref = xy[used]
    ext = np.ptp(ref, axis=0)
    scale = 0.86 * (size - 32) / max(float(ext.max()), 1e-3)
    mid = ref.mean(axis=0)
    pts = (xy - mid) * scale + (size - 1) * 0.5
    img_pts = np.empty_like(pts)
    img_pts[:, 0] = pts[:, 0]
    img_pts[:, 1] = (size - 1) - pts[:, 1]

    canvas = np.full((size, size, 3), 36, dtype=np.uint8)
    mask = np.zeros((size, size), dtype=np.uint8)
    # Depth buffer (higher = closer). Paint shaded hull with correct occlusion.
    zbuf = np.full((size, size), -1e9, dtype=np.float32)
    v0 = vv[faces[:, 0]]
    v1 = vv[faces[:, 1]]
    v2 = vv[faces[:, 2]]
    normals = np.cross(v1 - v0, v2 - v0)
    if view == "front":
        facing = normals[:, 0]
    elif view == "side":
        facing = -normals[:, 2]
    else:
        facing = normals[:, 1]
    ndot = depth[faces].mean(axis=1)
    dmin, dmax = float(ndot.min()), float(ndot.max())
    shade = np.clip(100 + (ndot - dmin) / max(dmax - dmin, 1e-6) * 120, 70, 230).astype(np.int32)

    # Prefer front-facing; fall back to all if too few
    front_ids = np.where(facing > 0)[0]
    if len(front_ids) < max(32, len(faces) // 10):
        front_ids = np.arange(len(faces))
    order = front_ids[np.argsort(ndot[front_ids])]
    for i in order:
        tri = np.round(img_pts[faces[i]]).astype(np.int32)
        xs, ys = tri[:, 0], tri[:, 1]
        minx, maxx = int(xs.min()), int(xs.max())
        miny, maxy = int(ys.min()), int(ys.max())
        if maxx < 0 or maxy < 0 or minx >= size or miny >= size:
            continue
        minx, maxx = max(minx, 0), min(maxx, size - 1)
        miny, maxy = max(miny, 0), min(maxy, size - 1)
        if maxx < minx or maxy < miny:
            continue
        tile = np.zeros((maxy - miny + 1, maxx - minx + 1), dtype=np.uint8)
        local = tri.copy()
        local[:, 0] -= minx
        local[:, 1] -= miny
        cv2.fillConvexPoly(tile, local, 255)
        ys_i, xs_i = np.where(tile > 0)
        if len(xs_i) == 0:
            continue
        gx = xs_i + minx
        gy = ys_i + miny
        z = float(ndot[i])
        closer = z >= zbuf[gy, gx]
        if not np.any(closer):
            continue
        gx, gy = gx[closer], gy[closer]
        zbuf[gy, gx] = z
        mask[gy, gx] = 255
        s = int(shade[i])
        canvas[gy, gx] = (s, min(255, s + 12), min(255, s + 24))

    # Soft outline for readability
    edges = cv2.Canny(mask, 40, 120)
    canvas[edges > 0] = (210, 215, 225)
    cv2.putText(canvas, view, (16, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (220, 220, 230), 2, cv2.LINE_AA)
    return Image.fromarray(canvas, "RGB").convert("RGBA")


def stage_one(stem: str, zh: str, en: str, res_path: str) -> dict:
    out_dir = OUT / "models_threeview" / stem
    out_dir.mkdir(parents=True, exist_ok=True)
    gr2 = fetch_resfile(res_path)
    print(f"[fighter] {stem} <- {res_path}")
    g = Gr2Meshes(gr2)
    name, verts, faces = pick_best_mesh(g)
    verts = auto_orient(verts, faces)
    print(f"  selected {name!r} verts={len(verts)} tris={len(faces)}")

    panels = []
    for view in ("front", "side", "top"):
        im = render_ortho(verts, faces, view)
        im.save(out_dir / f"{view}.png")
        panels.append(im)
    strip = Image.new("RGBA", (SIZE * 3 + 16, SIZE), (20, 22, 28, 255))
    for i, im in enumerate(panels):
        strip.paste(im, (i * (SIZE + 8), 0))
    bar = Image.new("RGBA", (strip.width, 36), (20, 22, 28, 255))
    ImageDraw.Draw(bar).text((12, 8), f"{zh} / {en}  {name}", fill=(200, 200, 210, 255))
    full = Image.new("RGBA", (strip.width, SIZE + 36), (20, 22, 28, 255))
    full.paste(bar, (0, 0))
    full.paste(strip, (0, 36))
    full.save(out_dir / "threeview_strip.png")
    return {"stem": stem, "status": "ok", "mesh": name, "verts": len(verts), "tris": int(len(faces))}


def main() -> None:
    results = []
    for stem, zh, en, res in FIGHTERS:
        try:
            results.append(stage_one(stem, zh, en, res))
        except Exception as e:
            print(f"[FAIL] {stem}: {e}")
            results.append({"stem": stem, "status": "fail", "error": str(e)})

    readme = OUT / "README.md"
    if readme.is_file():
        text = readme.read_text(encoding="utf-8")
        marker = "## fighters threeview"
        rows = [
            "",
            marker,
            "",
            "舰载机正交三视图（端游 GR2 · FileInfo.Meshes 正确解析，无立绘）：",
            "",
            "| 目录 | 状态 |",
            "|------|------|",
        ]
        for r in results:
            if r["status"] == "ok":
                rows.append(
                    f"| `models_threeview/{r['stem']}/` | ok {r['mesh']} verts={r['verts']} tris={r['tris']} |"
                )
            else:
                rows.append(f"| `models_threeview/{r['stem']}/` | fail {r.get('error')} |")
        rows.append("")
        block = "\n".join(rows)
        if marker in text:
            text = text.split(marker)[0].rstrip() + "\n" + block
        else:
            text = text.rstrip() + "\n" + block
        # fix table line
        text = text.replace(
            "| models_threeview/ | 舰船正交三视图（舰载机三视暂缺） |",
            "| models_threeview/ | 舰船 + 舰载机正交三视图 |",
        )
        readme.write_text(text, encoding="utf-8")

    ok = sum(1 for r in results if r["status"] == "ok")
    print(f"done ok={ok}/{len(results)}")


if __name__ == "__main__":
    main()
