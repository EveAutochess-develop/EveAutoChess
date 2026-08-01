# -*- coding: utf-8 -*-
"""Aft direction for a TQ hull, taken from its SOF engine boosters.

`auto_orient` guesses the bow from cross-section span, which reverses hulls whose
widest point is forward, and guesses the length axis from cross-section symmetry,
which loses to a superstructure wider than the fuselage. The nozzle cloud settles
both and is the authority whenever the hull has a booster record.

Note the SOF transform's rotation carries no usable facing: every booster on every
hull has Z basis exactly [0,0,1], so the plume axis is a hull-space constant. What
does discriminate is where the cloud sits relative to the hull centroid. A booster
may hang off a mid-hull pylon rather than the transom, so this uses the plume-length
weighted centroid of the whole cloud and reports how unanimous the nozzles are.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

BOOSTERS = Path(__file__).resolve().parent / "_extracted" / "sof_hull_boosters.json"


def hull_aft_axis(hull: str, hull_centroid: np.ndarray) -> np.ndarray | None:
    """Raw model-space unit vector pointing from the hull toward its stern.

    `hull_centroid` is required and must come from the mesh: measuring the cloud
    against its own mean cancels out to ~0 and returns pure noise.

    Returns None when the hull has no booster record, so callers fall back to the
    span heuristic.
    """
    if not BOOSTERS.is_file():
        return None
    doc = json.loads(BOOSTERS.read_text(encoding="utf-8"))
    items = (doc.get(hull) or {}).get("items") or []
    if not items:
        return None

    pos = []
    weight = []
    for it in items:
        t = np.asarray(it["transform"], dtype=np.float64)
        pos.append(t[3, :3])
        weight.append(max(float(np.linalg.norm(t[2, :3])), 1e-6))
    pos_arr = np.asarray(pos)
    w = np.asarray(weight)
    centre = np.asarray(hull_centroid, dtype=np.float64)
    aft = (pos_arr - centre) * w[:, None]
    v = aft.sum(axis=0)
    n = float(np.linalg.norm(v))
    if n < 1e-6:
        return None
    return v / n


def aft_report(hull: str, hull_centroid: np.ndarray) -> str:
    doc = json.loads(BOOSTERS.read_text(encoding="utf-8"))
    items = (doc.get(hull) or {}).get("items") or []
    pos = np.asarray([it["transform"][3][:3] for it in items], dtype=np.float64)
    axis = hull_aft_axis(hull, hull_centroid)
    if axis is None:
        return f"sof {hull}: no boosters"
    proj = (pos - hull_centroid) @ axis
    return (
        f"sof {hull}: n={len(pos)} aft={np.round(axis, 3)} "
        f"aft_side={int((proj > 0).sum())}/{len(pos)} "
        f"proj=[{proj.min():.0f},{proj.max():.0f}]"
    )
