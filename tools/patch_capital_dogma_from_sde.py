# -*- coding: utf-8 -*-
"""Patch capital/FAX ship JSON hull stats from TQ SDE dgmTypeAttributes."""
from __future__ import annotations

import csv
import json
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project")
SDE = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache")
SHIPS = ROOT / "data" / "ships"

SHIP_TYPE_IDS = {
    111: 19720,  # Revelation
    112: 19724,  # Moros
    113: 19726,  # Phoenix
    114: 19722,  # Naglfar
    121: 23757,  # Archon
    122: 23915,  # Chimera
    123: 23911,  # Thanatos
    124: 24483,  # Nidhoggur
    131: 37604,  # Apostle
    132: 37605,  # Minokawa
    133: 37606,  # Lif
    134: 37607,  # Ninazu
}

WANT_ATTRS = {
    "radius",
    "shieldCapacity",
    "armorHP",
    "hp",
    "signatureRadius",
    "scanResolution",
    "maxVelocity",
    "capacitorCapacity",
    "rechargeRate",
    "scanRadarStrength",
    "scanLadarStrength",
    "scanMagnetometricStrength",
    "scanGravimetricStrength",
    "shieldEmDamageResonance",
    "shieldThermalDamageResonance",
    "shieldKineticDamageResonance",
    "shieldExplosiveDamageResonance",
    "armorEmDamageResonance",
    "armorThermalDamageResonance",
    "armorKineticDamageResonance",
    "armorExplosiveDamageResonance",
    "emDamageResonance",
    "thermalDamageResonance",
    "kineticDamageResonance",
    "explosiveDamageResonance",
}


def _clean(s: str) -> str:
    return s.lstrip("\ufeff").strip().strip('"')


def load_attr_names() -> dict[int, str]:
    path = SDE / "dgmAttributeTypes.csv"
    out: dict[int, str] = {}
    with path.open(encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if not row or len(row) < 2 or not row[0]:
                continue
            try:
                aid = int(_clean(row[0]))
            except ValueError:
                continue
            out[aid] = row[1]
    return out


def load_type_attrs(type_ids: set[int], attrs: dict[int, str]) -> dict[int, dict[str, float]]:
    path = SDE / "dgmTypeAttributes.csv"
    vals = {tid: {} for tid in type_ids}
    with path.open(encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if not row or len(row) < 2 or not row[0]:
                continue
            try:
                tid = int(_clean(row[0]))
            except ValueError:
                continue
            if tid not in type_ids:
                continue
            try:
                aid = int(_clean(row[1]))
            except ValueError:
                continue
            name = attrs.get(aid, "")
            if name not in WANT_ATTRS:
                continue
            raw = row[3] if len(row) > 3 and row[3] not in ("", None) else (row[2] if len(row) > 2 else "0")
            if raw == "":
                raw = "0"
            vals[tid][name] = float(raw)
    return vals


def sensor_strength(st: dict[str, float]) -> float:
    return max(
        float(st.get("scanRadarStrength", 0.0)),
        float(st.get("scanLadarStrength", 0.0)),
        float(st.get("scanMagnetometricStrength", 0.0)),
        float(st.get("scanGravimetricStrength", 0.0)),
    )


def resonance_to_resist(resonance: float) -> float:
    return max(0.0, min(0.9, 1.0 - float(resonance)))


def layer_resists(st: dict[str, float], prefix: str) -> dict[str, float]:
    if prefix:
        mapping = {
            "emp": f"{prefix}EmDamageResonance",
            "thermal": f"{prefix}ThermalDamageResonance",
            "kinetic": f"{prefix}KineticDamageResonance",
            "explosive": f"{prefix}ExplosiveDamageResonance",
        }
    else:
        mapping = {
            "emp": "emDamageResonance",
            "thermal": "thermalDamageResonance",
            "kinetic": "kineticDamageResonance",
            "explosive": "explosiveDamageResonance",
        }
    out: dict[str, float] = {}
    for k, attr in mapping.items():
        if attr in st:
            out[k] = round(resonance_to_resist(st[attr]), 4)
        else:
            out[k] = 0.2
    return out


def patch_ship(ship_id: int, type_id: int, st: dict[str, float]) -> None:
    path = SHIPS / f"{ship_id}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    star0 = (data.get("stars") or [{}])[0]
    shield = float(st.get("shieldCapacity", star0.get("shield_hp", 0)))
    armor = float(st.get("armorHP", star0.get("armor_hp", 0)))
    structure = float(st.get("hp", star0.get("structure_hp", 0)))
    radius = float(st.get("radius", 0.0))
    if radius <= 0.0:
        radius = float(data.get("model_long_axis", 0.0))

    data["type_id"] = type_id
    data["signature_radius"] = float(st.get("signatureRadius", data.get("signature_radius", 0)))
    data["scan_resolution"] = float(st.get("scanResolution", data.get("scan_resolution", 0)))
    data["speed"] = float(st.get("maxVelocity", data.get("speed", 0)))
    data["sensor_strength"] = sensor_strength(st)
    ## Logistics / FAX: design rule sensor_strength ×5 (SHIP_STATS_V2).
    if bool(data.get("is_logistic", False)):
        data["sensor_strength"] = float(data["sensor_strength"]) * 5.0
    data["capacitor_capacity"] = float(st.get("capacitorCapacity", data.get("capacitor_capacity", 0)))
    recharge_ms = float(st.get("rechargeRate", 0.0))
    if recharge_ms > 0.0:
        data["capacitor_recharge_s"] = round(recharge_ms / 1000.0, 3)
    if radius > 0.0:
        data["model_long_axis"] = radius

    shield_res = layer_resists(st, "shield")
    armor_res = layer_resists(st, "armor")
    structure_res = layer_resists(st, "")

    for i, star in enumerate(data.get("stars", [])):
        mul = float(i + 1)
        star["shield_hp"] = round(shield * mul, 1)
        star["armor_hp"] = round(armor * mul, 1)
        star["structure_hp"] = round(structure * mul, 1)
        star["shield_resist"] = dict(shield_res)
        star["armor_resist"] = dict(armor_res)
        star["structure_resist"] = dict(structure_res)

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"patched {ship_id} type={type_id} axis={data.get('model_long_axis')} "
        f"sensor={data.get('sensor_strength')} cap={data.get('capacitor_capacity')}/"
        f"{data.get('capacitor_recharge_s')}s hp={shield}/{armor}/{structure}"
    )


def main() -> None:
    attrs = load_attr_names()
    type_ids = set(SHIP_TYPE_IDS.values())
    vals = load_type_attrs(type_ids, attrs)
    dump = ROOT / "data" / "_extracted" / "capital_dogma_from_sde.json"
    dump.parent.mkdir(parents=True, exist_ok=True)
    dump.write_text(json.dumps(vals, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for ship_id, type_id in SHIP_TYPE_IDS.items():
        st = vals.get(type_id, {})
        if not st:
            print(f"WARN missing dogma for {ship_id} type {type_id}")
            continue
        patch_ship(ship_id, type_id, st)


if __name__ == "__main__":
    main()
