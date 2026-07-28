# -*- coding: utf-8 -*-
"""Canonical PC asset mapping keyed by English name / compatibility keys."""
from __future__ import annotations

from eve_pc.pc_drone_map import PC_DRONE_GR2

# name_en -> res:/ path
# Ships are intentionally left sparse until each hull is verified against the PC
# client. The generic importer consumes this table without adding scenario-
# specific branches; drones already use the same contract.
PC_SHIP_GR2_BY_NAME_EN: dict[str, str] = {}

# model_key -> res:/ path
PC_SHIP_GR2_BY_MODEL_KEY: dict[str, str] = {}


def canonical_pc_res_path(data: dict) -> str:
    name_en = str(data.get("name_en") or "").strip()
    model_key = str(data.get("model_key") or "").strip()
    if name_en and name_en in PC_SHIP_GR2_BY_NAME_EN:
        return PC_SHIP_GR2_BY_NAME_EN[name_en]
    if model_key and model_key in PC_SHIP_GR2_BY_MODEL_KEY:
        return PC_SHIP_GR2_BY_MODEL_KEY[model_key]
    if model_key and model_key in PC_DRONE_GR2:
        return PC_DRONE_GR2[model_key]
    return ""
