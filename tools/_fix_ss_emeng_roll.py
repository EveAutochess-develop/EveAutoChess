# -*- coding: utf-8 -*-
"""Add model_roll_deg to ss_emeng bow_fit and rotate nozzle norms around Z."""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np

PACKS = [
    Path(r"H:\game_dev\eveautochess-dev\godot_project\assets\models\ships\ss_emeng\engine_boosters.json"),
    Path(r"H:\game_dev\eveautochess-design\docs\_review\preview\pirate_faction_ships\pc_models\ss_emeng\engine_boosters.json"),
]

# +90° about longitudinal Z after yaw: moves former +X (side bulge) onto +Y (up).
ROLL_DEG = 90.0


def main() -> None:
    a = math.radians(ROLL_DEG)
    rz = np.array(
        [
            [math.cos(a), -math.sin(a), 0.0],
            [math.sin(a), math.cos(a), 0.0],
            [0.0, 0.0, 1.0],
        ]
    )
    for path in PACKS:
        if not path.is_file():
            print("skip missing", path)
            continue
        doc = json.loads(path.read_text(encoding="utf-8"))
        fit = doc.get("bow_fit") or {}
        norms = fit.get("nozzles_ship_norm") or []
        # norms are 0..1 in post-yaw AABB. Rolling the mesh around Z keeps Z norm,
        # but X/Y swap in AABB space only if we also rebuild AABB. Simpler contract:
        # store roll separately; norms stay in post-yaw-pre-roll space and ShipUnit
        # applies roll to the model root — live AABB after roll remaps correctly IF
        # norms are in model-local after yaw+roll.
        #
        # Recompute: treat norm as point in unit cube, map to [-0.5,0.5], rotate, back.
        new_norms = []
        for n in norms:
            p = np.array([float(n[0]) - 0.5, float(n[1]) - 0.5, float(n[2]) - 0.5])
            q = rz @ p
            new_norms.append(
                [
                    round(float(q[0] + 0.5), 6),
                    round(float(q[1] + 0.5), 6),
                    round(float(q[2] + 0.5), 6),
                ]
            )
        fit["model_roll_deg"] = ROLL_DEG
        fit["nozzles_ship_norm"] = new_norms
        fit["roll_note"] = "Nightmare dorsal bulge: +90° roll about bow-stern (Z) so bulge is +Y up"
        doc["bow_fit"] = fit
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print("updated", path, "roll=", ROLL_DEG, "nozzles=", len(new_norms))


if __name__ == "__main__":
    main()
