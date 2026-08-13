# -*- coding: utf-8 -*-
"""Re-export TQ titans to §0 GLB with UV (fixes solid silhouette tint).

Root causes:
- Fake-pointer stride is 1MB; section-0 offsets ≥1MB mis-decode as empty
  sections (Avatar verts). Resolve via Granny pointer_fixups instead.
- TQ ship UV is float16 at the *end* of the vertex (stride-4), not +12.
  Using +12 yields (0,0) → albedo samples one texel → solid silhouette.
"""
from __future__ import annotations

import json
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
from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2  # noqa: E402
from io_scene_gr2.gr2.decompress import DecompressionError, decompress_section  # noqa: E402
from io_scene_gr2.gr2.decompress.bitknit import decode_bitknit_state7_stream  # noqa: E402
from io_scene_gr2.gr2.file import read_gr2  # noqa: E402
from io_scene_gr2.gr2.fixup import PointerRef, decode_fake_pointer, load_sections  # noqa: E402
from stage_mining_threeviews import auto_orient  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"

TITANS = [
    {
        "key": "tq_titan_a",
        "bake_gr2": "res:/dx9/model/ship/amarr/titan/at1/at1_t1.gr2",
        "gr2": [
            "res:/dx9/model/ship/amarr/titan/at1/at1_t1.gr2",
            "res:/dx9/model/ship/amarr/titan/at1/at1_t1_lowdetail.gr2",
        ],
    },
    {
        "key": "tq_titan_c",
        "bake_gr2": "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1.gr2",
        "gr2": [
            "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1.gr2",
            "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1_lowdetail.gr2",
        ],
    },
    {
        "key": "tq_titan_g",
        "bake_gr2": "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1.gr2",
        "gr2": [
            "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1.gr2",
            "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1_lowdetail.gr2",
        ],
    },
    {
        "key": "tq_titan_m",
        "bake_gr2": "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1.gr2",
        "gr2": [
            "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1.gr2",
            "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1_lowdetail.gr2",
        ],
    },
]

EDGE_MED_MAX = 8000.0
## Only triangles longer than this fraction of the model extent are treated as
## garbage spikes; measured TQ titan panels top out at ~0.18.
SPIKE_EDGE_FRAC = 0.25
# Prefer TQ ship packing: stride 32 UV@28, then 28 UV@24 (see import_mining_pc_meshes).
STRIDES = (32, 28, 24, 36, 40, 48, 20, 16)


# Granny struct field offsets. Arrays are packed count(u32) + pointer, no padding,
# so field offsets differ between 32-bit and 64-bit pointer files (TQ ships and
# G/M wrecks are 64-bit; A/C wreck GR2s are 32-bit).
LAYOUT_64 = {
    "file_meshes": 84,
    "mesh_vertex_data": 8,
    "mesh_topology": 28,
    "vertex_data_verts": 8,
    "topology_indices32": 12,
    "topology_indices16": 24,
}
LAYOUT_32 = {
    "file_meshes": 52,
    "mesh_vertex_data": 4,
    "mesh_topology": 16,
    "vertex_data_verts": 4,
    "topology_indices32": 8,
    "topology_indices16": 16,
}


class PartialSectionBackend:
    """Keep the decoded prefix when BitKnit2 stops before the section ends.

    Some TQ hulls (gt1_t1.gr2) only decode ~90% of section 0, which otherwise
    forces the whole export down to a LOD-40 mesh that reads as a holey hull.
    The prefix usually already holds the full-detail mesh, so keep it, pad the
    tail so pointer fixups still apply, and record the honest boundary in
    `valid_len` — reads past it are refused rather than fed padding.
    """

    def __init__(self) -> None:
        self.valid_len: dict[int, int] = {}

    def decompress(self, section, compressed: bytes) -> bytes:
        try:
            out = decompress_section(section, compressed)
        except DecompressionError:
            out = self._decoded_prefix(section, compressed)
        self.valid_len[section.index] = len(out)
        if len(out) < section.expanded_size:
            out = out + bytes(section.expanded_size - len(out))
        return out

    @staticmethod
    def _decoded_prefix(section, compressed: bytes) -> bytes:
        if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
            return b""
        try:
            result = decode_bitknit_state7_stream(compressed, section.expanded_size)
        except Exception:  # noqa: BLE001 - any decode failure means no usable prefix
            return b""
        return bytes(result.output)


class MultiSectionGr2:
    """GR2 reader that resolves pointers via fixup table (handles >1MB §0)."""

    def __init__(self, path: Path, *, allow_partial: bool = False):
        gr2 = read_gr2(path)
        backend = PartialSectionBackend() if allow_partial else None
        self.loaded = load_sections(gr2, backend)
        self._valid_len: dict[int, int] = backend.valid_len if backend else {}
        self._fixups = {
            (f.source_section, f.source_offset): f.target for f in self.loaded.pointer_fixups
        }
        self.nsec = len(self.loaded.sections_fixed)
        self.ptr_size = gr2.header.pointer_size // 8
        self.layout = LAYOUT_64 if self.ptr_size == 8 else LAYOUT_32

    def off(self, field: str) -> int:
        return self.layout[field]

    def resolve_ptr(self, owner: PointerRef, ptr_field_off: int) -> PointerRef | None:
        abs_off = owner.offset + ptr_field_off
        hit = self._fixups.get((owner.section, abs_off))
        if hit is not None:
            return hit
        fmt = "<Q" if self.ptr_size == 8 else "<I"
        blob = self.read_bytes(owner, ptr_field_off + self.ptr_size)
        raw = struct.unpack_from(fmt, blob, ptr_field_off)[0]
        return decode_fake_pointer(raw, self.nsec)

    def u32(self, ref: PointerRef, off: int) -> int:
        return struct.unpack_from("<I", self.read_bytes(ref, off + 4), off)[0]

    def aor(self, ref: PointerRef, off: int) -> tuple[int, PointerRef | None]:
        count = self.u32(ref, off)
        return count, self.resolve_ptr(ref, off + 4)

    def cstr(self, ref: PointerRef | None) -> str:
        if not ref:
            return ""
        try:
            data = self.loaded.read_ref(ref)
        except ValueError:
            return ""
        end = data.find(b"\x00")
        return data[: end if end >= 0 else len(data)].decode("ascii", "replace")

    def read_bytes(self, ref: PointerRef, size: int) -> bytes:
        limit = self._valid_len.get(ref.section)
        if limit is not None and ref.offset + size > limit:
            raise ValueError(
                f"read past decoded prefix {ref.section}:{ref.offset}+{size} > {limit}"
            )
        return self.loaded.read_ref(ref, size)

    def mesh_list(self) -> list[tuple[str, PointerRef]]:
        root = PointerRef(0, 0)
        count, arr = self.aor(root, self.off("file_meshes"))
        if not arr or count <= 0:
            raise RuntimeError(f"no meshes count={count}")
        out: list[tuple[str, PointerRef]] = []
        for i in range(count):
            mref = self.resolve_ptr(arr, i * self.ptr_size)
            if not mref:
                continue
            nref = self.resolve_ptr(mref, 0)
            name = self.cstr(nref) or f"mesh_{i}"
            name = name.encode("ascii", "replace").decode("ascii")
            out.append((name, mref))
        return out


def _uv_looks_valid(uvs: np.ndarray) -> bool:
    if uvs is None or uvs.shape[0] < 32 or not np.isfinite(uvs).all():
        return False
    span_u = float(uvs[:, 0].max() - uvs[:, 0].min())
    span_v = float(uvs[:, 1].max() - uvs[:, 1].min())
    if span_u < 0.15 or span_v < 0.15:
        return False
    span = span_u + span_v
    nz = float(np.mean((np.abs(uvs[:, 0]) > 1e-3) | (np.abs(uvs[:, 1]) > 1e-3)))
    med = float(np.median(np.abs(uvs)))
    return 0.05 < span < 20.0 and med < 8.0 and nz > 0.2


def _uv_in01_score(uvs: np.ndarray) -> float:
    in01 = float(
        np.mean(
            (uvs[:, 0] >= -0.05)
            & (uvs[:, 0] <= 1.05)
            & (uvs[:, 1] >= -0.05)
            & (uvs[:, 1] <= 1.05)
        )
    )
    span_u = float(uvs[:, 0].max() - uvs[:, 0].min())
    span_v = float(uvs[:, 1].max() - uvs[:, 1].min())
    med_u = float(np.median(uvs[:, 0]))
    med_v = float(np.median(uvs[:, 1]))
    ## Penalize collapsed islands (almost all verts on one texel).
    collapse = 0.0
    if (med_u > 0.92 and med_v > 0.92) or (abs(med_u) < 0.04 and abs(med_v) < 0.04):
        collapse = 4.0
    return in01 * 10.0 + min(span_u, 1.2) + min(span_v, 1.2) - collapse


def _try_uvs(blob: bytes, vcount: int, stride: int) -> tuple[np.ndarray, int] | None:
    """Score every 16-bit pair as float16 *and* unorm16.

    Vanquisher hull/wreck store UV as unorm16 in the last 4 bytes (atlas ~0.02–0.82).
    Packed normals remapped as unorm16 look like a perfect 0–1 sheet and used to
    beat the real atlas (preview 'lost textures'). Tail unorm16 that does *not*
    fill the full sheet gets a bonus. G wreck still wins as float16 @+16.
    """
    if stride < 16 or stride % 2 != 0:
        return None
    u16 = np.frombuffer(blob, dtype="<u2").reshape(vcount, stride // 2)
    tail_col = stride // 2 - 2

    def _from_col(col: int) -> np.ndarray:
        raw = u16[:, col : col + 2].copy()
        return raw.view("<f2").astype(np.float64).reshape(vcount, 2)

    best: np.ndarray | None = None
    best_score = -1.0
    best_off = -1
    ## Skip position xyz (first 12 bytes = 6 u16). Last pair is stride/2-2.
    for col in range(6, stride // 2 - 1):
        cands = (
            ("f16", _from_col(col)),
            ## Vanquisher / some wrecks store UV as unorm16, not float16.
            ("unorm16", u16[:, col : col + 2].astype(np.float64) / 65535.0),
        )
        for kind, cand in cands:
            if not _uv_looks_valid(cand):
                continue
            score = _uv_in01_score(cand)
            mx = float(np.max(cand))
            mn = float(np.min(cand))
            ## Packed SNORM/UNORM attrs fill 0–1; real Angel atlas does not.
            if kind == "unorm16" and mn <= 0.02 and mx >= 0.98:
                score -= 2.5
            if kind == "unorm16" and col == tail_col and mx < 0.92:
                score += 3.0
            if score > best_score:
                best_score = score
                best = cand
                best_off = col * 2
    if best is None:
        return None
    out = best.copy()
    out[:, 1] = 1.0 - out[:, 1]
    return out, best_off


def _extract_best(g: MultiSectionGr2) -> tuple[np.ndarray, np.ndarray, np.ndarray, int, int]:
    best = None  # score tuple then payload
    for name, mref in g.mesh_list():
        try:
            pvd = g.resolve_ptr(mref, g.off("mesh_vertex_data"))
            topo = g.resolve_ptr(mref, g.off("mesh_topology"))
            if not pvd or not topo:
                continue
            vcount, varr = g.aor(pvd, g.off("vertex_data_verts"))
            if not varr or vcount < 32:
                continue
            i16_count, i16_arr = g.aor(topo, g.off("topology_indices16"))
            if i16_arr and i16_count >= 3:
                idx = np.frombuffer(g.read_bytes(i16_arr, i16_count * 2), dtype="<u2").astype(np.int32)
            else:
                i32_count, i32_arr = g.aor(topo, g.off("topology_indices32"))
                if not i32_arr or i32_count < 3:
                    continue
                idx = np.frombuffer(g.read_bytes(i32_arr, i32_count * 4), dtype="<u4").astype(np.int32)
            usable = len(idx) - (len(idx) % 3)
            faces_all = idx[:usable].reshape(-1, 3)
            faces_all = faces_all[(faces_all < vcount).all(axis=1)]
            if len(faces_all) < 32:
                continue
            for stride in STRIDES:
                need = vcount * stride
                try:
                    blob = g.read_bytes(varr, need)
                except ValueError:
                    continue
                if len(blob) < need:
                    continue
                verts = np.zeros((vcount, 3), dtype=np.float64)
                for i in range(vcount):
                    verts[i] = struct.unpack_from("<fff", blob, i * stride)
                if not np.isfinite(verts).all():
                    # Allow sparse garbage; filter below.
                    pass
                mag = np.linalg.norm(verts, axis=1)
                sane = np.isfinite(mag) & (mag < 1e6)
                if int(sane.sum()) < 32:
                    continue
                p50 = float(np.median(mag[sane]))
                keep = sane & (mag <= max(p50 * 8.0, 50.0))
                faces = faces_all[keep[faces_all].all(axis=1)]
                if len(faces) < 32:
                    continue
                e1 = np.linalg.norm(verts[faces[:, 0]] - verts[faces[:, 1]], axis=1)
                e2 = np.linalg.norm(verts[faces[:, 1]] - verts[faces[:, 2]], axis=1)
                e3 = np.linalg.norm(verts[faces[:, 2]] - verts[faces[:, 0]], axis=1)
                emax = np.maximum(np.maximum(e1, e2), e3)
                med = float(np.median(emax))
                if med < 1e-4 or med > EDGE_MED_MAX:
                    continue
                # `med * 6` only validates the stride guess: real hull panels reach
                # ~0.18 × model extent, so culling by it punches holes in the hull.
                # Keep every in-range face and drop only cross-model spikes.
                if int((emax <= med * 6.0).sum()) < 32:
                    continue
                used = np.unique(faces.reshape(-1))
                extent = float(np.max(np.ptp(verts[used], axis=0)))
                faces = faces[emax <= extent * SPIKE_EDGE_FRAC]
                if len(faces) < 32:
                    continue
                uv_hit = _try_uvs(blob, vcount, stride)
                if uv_hit is None:
                    uvs = np.zeros((vcount, 2), dtype=np.float64)
                    uv_off = -1
                else:
                    uvs, uv_off = uv_hit
                lod_pen = 1 if "LOD" in name.upper() else 0
                # Prefer: has UV, more tris, smaller edges, non-LOD, larger stride (32>).
                score = (
                    0 if uv_off >= 0 else 1,
                    lod_pen,
                    -len(faces),
                    med,
                    -stride,
                )
                if best is None or score < best[0]:
                    best = (score, verts, faces, uvs, stride, uv_off, name)
                    print(
                        f"    cand {name!r} stride={stride} tris={len(faces)} "
                        f"edge_med={med:.3f} uv_off={uv_off}"
                    )
        except Exception as e:
            print(f"    skip {name!r}: {e}")
            continue
    if best is None:
        raise RuntimeError("no usable mesh")
    _score, verts, faces, uvs, stride, uv_off, name = best
    print(f"  SELECT {name!r} stride={stride} uv_off={uv_off} verts={len(verts)} tris={len(faces)}")
    return verts, faces, uvs, stride, uv_off


def write_obj(verts: np.ndarray, faces: np.ndarray, uvs: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", errors="replace") as f:
        f.write("# titan with UV\n")
        for v in verts:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        for uv in uvs:
            f.write(f"vt {uv[0]:.6f} {uv[1]:.6f}\n")
        for tri in faces:
            a, b, c = int(tri[0]) + 1, int(tri[1]) + 1, int(tri[2]) + 1
            f.write(f"f {a}/{a} {b}/{b} {c}/{c}\n")


def export_one(t: dict) -> dict:
    last = ""
    for res in t["gr2"]:
        try:
            print(f"[mesh] {t['key']} <- {res}")
            g = MultiSectionGr2(Path(fetch_resfile(res)), allow_partial=True)
            verts, faces, uvs, stride, uv_off = _extract_best(g)
            if uv_off < 0:
                raise RuntimeError("mesh has no usable UV")
            verts = auto_orient(verts, faces)
            out = PACKS / t["key"]
            out.mkdir(parents=True, exist_ok=True)
            obj = out / "_uv.obj"
            write_obj(verts, faces, uvs, obj)
            glb = out / "model.glb"
            assimp_convert(obj, glb, "glb2")
            obj.unlink(missing_ok=True)
            bake_bundle_for_res_path(t["key"], t["bake_gr2"])
            return {
                "key": t["key"],
                "status": "ok",
                "res": res,
                "stride": stride,
                "uv_off": uv_off,
                "verts": int(len(verts)),
                "tris": int(len(faces)),
                "glb": glb.stat().st_size,
            }
        except Exception as e:
            last = str(e)
            print(f"  fail: {e}")
    return {"key": t["key"], "status": "fail", "error": last}


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass
    reports = [export_one(t) for t in TITANS]
    for r in reports:
        if r.get("status") != "ok":
            continue
        p = PACKS / r["key"] / "model.glb"
        data = p.read_bytes()
        jlen = struct.unpack_from("<I", data, 12)[0]
        j = json.loads(data[20 : 20 + jlen])
        attrs = []
        for m in j.get("meshes", []):
            for pr in m.get("primitives", []):
                attrs.append(sorted(pr.get("attributes", {}).keys()))
        r["glb_attrs"] = attrs
        print(r["key"], "attrs", attrs)
    (PACKS / "_titan_uv_export_report.json").write_text(
        json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    ok = sum(1 for r in reports if r.get("status") == "ok")
    print(f"done ok={ok}/{len(reports)}")


if __name__ == "__main__":
    main()
