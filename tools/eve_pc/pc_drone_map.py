# -*- coding: utf-8 -*-
"""Map project drone model_key → EVE PC resfile paths (Tranquility layout)."""
from __future__ import annotations

# model_key -> res:/ path (modern race/light|medium|heavy tier folders)
PC_DRONE_GR2: dict[str, str] = {
    # light (t1 mesh)
    "wrj_a_shiseng": "res:/dx9/model/drone/amarr/light/adl1/adl1_t1.gr2",
    "wrj_j_dahuangfeng": "res:/dx9/model/drone/caldari/light/cdl1/cdl1_t1.gr2",
    "wrj_g_dijingling": "res:/dx9/model/drone/gallente/light/gdl1/gdl1_t1.gr2",
    "wrj_m_mwushi": "res:/dx9/model/drone/minmatar/light/mdl1/mdl1_t1.gr2",
    # medium
    "wrj_a_shentouzhe": "res:/dx9/model/drone/amarr/medium/adm1/adm1_t1.gr2",
    "wrj_j_jinxing": "res:/dx9/model/drone/caldari/medium/cdm1/cdm1_t1.gr2",
    "wrj_g_zhanchui": "res:/dx9/model/drone/gallente/medium/gdm1/gdm1_t1.gr2",
    "wrj_m_waerjili": "res:/dx9/model/drone/minmatar/medium/mdm1/mdm1_t1.gr2",
    # heavy
    "wrj_a_zhizheng": "res:/dx9/model/drone/amarr/heavy/adh1/adh1_t1.gr2",
    "wrj_j_hufeng": "res:/dx9/model/drone/caldari/heavy/cdh1/cdh1_t2.gr2",  # t1 FileInfo broken
    "wrj_g_shirenmo": "res:/dx9/model/drone/gallente/heavy/gdh1/gdh1_t1.gr2",
    "wrj_m_kuangzhanshi": "res:/dx9/model/drone/minmatar/heavy/mdh1/mdh1_t1.gr2",
    # FAX heavy repair drones (same race heavy hulls as maintenance bots)
    "heavy_repair_amarr": "res:/dx9/model/drone/amarr/heavy/adh1/adh1_t1.gr2",
    "heavy_repair_caldari": "res:/dx9/model/drone/caldari/heavy/cdh1/cdh1_t2.gr2",
    "heavy_repair_gallente": "res:/dx9/model/drone/gallente/heavy/gdh1/gdh1_t1.gr2",
    "heavy_repair_minmatar": "res:/dx9/model/drone/minmatar/heavy/mdh1/mdh1_t1.gr2",
    # ORE mining excavator (Rorqual drones)
    "wrj_ore_excavator": "res:/dx9/model/drone/ore/heavy/oredh2/oredh2_t1.gr2",
}
