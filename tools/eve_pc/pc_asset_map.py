# -*- coding: utf-8 -*-
"""Canonical PC asset mapping keyed by English name / compatibility keys."""
from __future__ import annotations

from eve_pc.pc_drone_map import PC_DRONE_GR2

# name_en -> res:/ path
# Ships are intentionally left sparse until each hull is verified against the PC
# client. The generic importer consumes this table without adding scenario-
# specific branches; drones already use the same contract.
PC_SHIP_GR2_BY_NAME_EN: dict[str, str] = {
    "Retriever": "res:/dx9/model/ship/ore/barge/oreba2/oreba2_t1.gr2",
    "Porpoise": "res:/dx9/model/ship/ore/battleship/oreb1/oreb1_t1.gr2",
    "Orca": "res:/dx9/model/ship/ore/freighter/orefr1/orefr1_t1.gr2",
    "Rorqual": "res:/dx9/model/ship/ore/capital/orecs1/orecs1_t1.gr2",
}

# model_key -> res:/ path
PC_SHIP_GR2_BY_MODEL_KEY: dict[str, str] = {
    "lhky_huixuanzhe": "res:/dx9/model/ship/ore/barge/oreba2/oreba2_t1.gr2",
    "lhky_haitun": "res:/dx9/model/ship/ore/battleship/oreb1/oreb1_t1.gr2",
    "lhky_nijijing": "res:/dx9/model/ship/ore/freighter/orefr1/orefr1_t1.gr2",
    "lhky_changxujing": "res:/dx9/model/ship/ore/capital/orecs1/orecs1_t1.gr2",
}


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
