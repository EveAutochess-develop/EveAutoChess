extends RefCounted
class_name PolicyObs
## Farm-isomorphic short vectors for Shop/Ops/Place (FourNetPack). Ranking table never enters.

const SHIP_DIM: int = 28
const EQ_DIM: int = 12
const D_DIM: int = 32
const OPS_OBS: int = 64
const MG_DIM: int = 201
const N_SHIP_SHOP: int = 6
const N_EQ_SHOP: int = 4
const MAX_CELLS: int = 64
const TITANS: PackedStringArray = ["amarr", "caldari", "gallente", "minmatar", "angel"]
const SIZES: PackedStringArray = ["S", "M", "L", "XL"]


static func shop_in_dim() -> int:
	return N_SHIP_SHOP * SHIP_DIM + N_EQ_SHOP * EQ_DIM + D_DIM + 8


static func encode_shop(policy: OnnxCpuPolicy, ctx: Dictionary) -> PackedFloat32Array:
	var feat: PackedFloat32Array = PackedFloat32Array()
	feat.resize(N_SHIP_SHOP * SHIP_DIM + N_EQ_SHOP * EQ_DIM)
	var shop: Array = TypedVariant.as_array(ctx.get("shop_slots", []))
	var equips: Array = TypedVariant.as_array(ctx.get("equipment_slots", []))
	for i: int in range(N_SHIP_SHOP):
		var sid: int = 0
		if i < shop.size():
			var slot: Dictionary = TypedVariant.as_dict(shop[i])
			if not TypedVariant.as_bool(slot.get("purchased", false), false):
				sid = TypedVariant.as_int(slot.get("ship_id", 0), 0)
		_blit(feat, i * SHIP_DIM, live_ship_vec(sid, 1))
	for i: int in range(N_EQ_SHOP):
		var eid: String = ""
		if i < equips.size():
			var es: Dictionary = TypedVariant.as_dict(equips[i])
			if not TypedVariant.as_bool(es.get("purchased", false), false):
				eid = str(es.get("id", ""))
		_blit(feat, N_SHIP_SHOP * SHIP_DIM + i * EQ_DIM, live_equip_vec(eid))
	var intent: PackedFloat32Array = _ops_intent(policy, ctx)
	var gold: float = TypedVariant.as_float(ctx.get("gold", 0), 0.0)
	var level: float = TypedVariant.as_float(ctx.get("level", 1), 1.0)
	var pieces: float = TypedVariant.as_float(ctx.get("piece_count", 0), 0.0)
	var extra: PackedFloat32Array = PackedFloat32Array([
		gold / 50.0,
		level / 20.0,
		TypedVariant.as_float(ctx.get("save_p", 0.0), 0.0),
		TypedVariant.as_float(ctx.get("scan_p", 0.0), 0.0),
		TypedVariant.as_float(ctx.get("xp_p", 0.0), 0.0),
		TypedVariant.as_float(ctx.get("sell_p", 0.0), 0.0),
		pieces / 12.0,
		1.0,
	])
	return _concat3(feat, intent, extra)


static func encode_ops(ctx: Dictionary) -> PackedFloat32Array:
	var gold: float = TypedVariant.as_float(ctx.get("gold", 0), 0.0)
	var level: float = TypedVariant.as_float(ctx.get("level", 1), 1.0)
	var xp: float = TypedVariant.as_float(ctx.get("xp", 0), 0.0)
	var rnd: float = TypedVariant.as_float(ctx.get("round", 1), 1.0)
	var field_n: float = TypedVariant.as_float(ctx.get("field_count", 0), 0.0)
	var hangar_n: float = TypedVariant.as_float(ctx.get("hangar_count", 0), 0.0)
	var bag_n: float = TypedVariant.as_float(ctx.get("bag_count", 0), 0.0)
	var win_s: float = TypedVariant.as_float(ctx.get("win_streak", 0), 0.0)
	var loss_s: float = TypedVariant.as_float(ctx.get("loss_streak", 0), 0.0)
	var titan: String = str(ctx.get("titan", "caldari"))
	var stance: PackedFloat32Array = TypedVariant.as_packed_f32(ctx.get("stance", PackedFloat32Array()))
	if stance.size() < 5:
		stance = PackedFloat32Array([0.2, 0.2, 0.2, 0.2, 0.2])
	var mode: String = str(ctx.get("security_mode", "nullsec"))
	var need: float = maxf(1.0, TypedVariant.as_float(ctx.get("xp_demand", 4), 4.0))
	var field_full: float = 1.0 if field_n >= maxf(1.0, level) else 0.0
	var vec: Array[float] = [
		gold / 50.0,
		minf(5.0, floorf(gold / 10.0)) / 5.0,
		level / 20.0,
		xp / 40.0,
		rnd / 20.0,
		field_n / 10.0,
		hangar_n / 10.0,
		bag_n / 8.0,
		TypedVariant.as_float(ctx.get("lives_frac", 1.0), 1.0),
		win_s / 8.0,
		loss_s / 8.0,
		TypedVariant.as_float(ctx.get("star_sum", 0), 0.0) / 20.0,
		TypedVariant.as_float(ctx.get("equip_sum", 0), 0.0) / 12.0,
		1.0,
		0.0,
		0.0,
		1.0 if mode != "lowsec" else 0.0,
		1.0 if mode == "lowsec" else 0.0,
	]
	var race_oh: PackedFloat32Array = _one_hot(_titan_index(titan), 5)
	for i: int in range(5):
		vec.append(race_oh[i])
	for i: int in range(5):
		vec.append(stance[i] if i < stance.size() else 0.2)
	vec.append(field_full)
	vec.append(xp / need)
	vec.append(1.0 if gold >= TypedVariant.as_float(ctx.get("buy_exp_cost", 4), 4.0) else 0.0)
	vec.append(0.0)
	vec.append(0.0)
	vec.append(0.0)
	vec.append(0.0)
	vec.append(0.0)
	vec.append(TypedVariant.as_float(ctx.get("has_cyno_hangar", 0.0), 0.0))
	vec.append(TypedVariant.as_float(ctx.get("has_covert_field", 0.0), 0.0))
	return _pad_arr(vec, OPS_OBS)


static func encode_place(ship_id: int, star: int, ctx: Dictionary, cell_mask: PackedFloat32Array) -> PackedFloat32Array:
	var ship_v: PackedFloat32Array = live_ship_vec(ship_id, star)
	var extra: PackedFloat32Array = PackedFloat32Array([
		TypedVariant.as_float(ctx.get("gold", 0), 0.0) / 50.0,
		TypedVariant.as_float(ctx.get("level", 1), 1.0) / 20.0,
		TypedVariant.as_float(ctx.get("field_count", 0), 0.0) / 10.0,
		TypedVariant.as_float(ctx.get("hangar_count", 0), 0.0) / 10.0,
		1.0,
		0.0,
		0.0,
		1.0,
	])
	var cells: PackedFloat32Array = PackedFloat32Array()
	cells.resize(MAX_CELLS)
	var n: int = mini(MAX_CELLS, cell_mask.size())
	for i: int in range(n):
		cells[i] = cell_mask[i]
	var intent: PackedFloat32Array = PackedFloat32Array()
	intent.resize(D_DIM)
	return _concat3(_concat3(ship_v, extra, cells), intent, PackedFloat32Array())


static func live_ship_vec(ship_id: int, star: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(SHIP_DIM)
	if ship_id <= 0 or DataStore == null:
		return out
	var hull: Dictionary = DataStore.get_ship(ship_id)
	if hull.is_empty():
		return out
	var st: Dictionary = DataStore.get_star_resolved(ship_id, maxi(1, star))
	var dmg: Dictionary = TypedVariant.as_dict(st.get("damage", {}))
	var dsum: float = (
		TypedVariant.as_float(dmg.get("emp", 0.0), 0.0)
		+ TypedVariant.as_float(dmg.get("thermal", 0.0), 0.0)
		+ TypedVariant.as_float(dmg.get("kinetic", 0.0), 0.0)
		+ TypedVariant.as_float(dmg.get("explosive", 0.0), 0.0)
	)
	var sz: String = _size_of(hull)
	var race: String = str(hull.get("race", "")).to_lower()
	out[0] = TypedVariant.as_float(hull.get("cost", 0.0), 0.0) / 30.0
	out[1] = TypedVariant.as_float(st.get("shield_hp", 0.0), 0.0) / 4000.0
	out[2] = TypedVariant.as_float(st.get("armor_hp", 0.0), 0.0) / 4000.0
	out[3] = TypedVariant.as_float(st.get("structure_hp", 0.0), 0.0) / 4000.0
	out[4] = TypedVariant.as_float(hull.get("speed", 0.0), 0.0) / 400.0
	out[5] = TypedVariant.as_float(hull.get("signature_radius", 0.0), 0.0) / 400.0
	out[6] = TypedVariant.as_float(hull.get("scan_resolution", 0.0), 0.0) / 800.0
	out[7] = TypedVariant.as_float(hull.get("attack_cycle_s", 0.0), 0.0) / 10.0
	out[8] = dsum / 400.0
	out[9] = 1.0 if TypedVariant.as_bool(hull.get("is_logistic", false), false) else 0.0
	out[10] = 1.0 if TypedVariant.as_bool(hull.get("deploy_enemy_half_only", false), false) else 0.0
	out[11] = 1.0 if TypedVariant.as_bool(hull.get("requires_cyno_entry", false), false) else 0.0
	var si: int = SIZES.find(sz)
	if si >= 0:
		out[12 + si] = 1.0
	var ri: int = TITANS.find(race)
	if ri >= 0:
		out[16 + ri] = 1.0
	out[21] = float(maxi(1, star)) / 3.0
	if TypedVariant.as_bool(hull.get("is_mining_ship", false), false):
		out[22] = minf(1.0, TypedVariant.as_float(hull.get("mining_gold_per_round", 0.0), 0.0) / 40.0)
	else:
		out[22] = minf(1.0, float(TypedVariant.as_array(hull.get("fetter_ids", [])).size()) / 6.0)
	out[23] = TypedVariant.as_float(hull.get("capacitor_capacity", 0.0), 0.0) / 4000.0
	return out


static func live_equip_vec(item_id: String) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(EQ_DIM)
	if item_id == "" or DataStore == null:
		return out
	var meta: Dictionary = DataStore.get_function_module(item_id)
	if meta.is_empty():
		return out
	var sz: String = str(meta.get("size", "S")).to_upper()
	var effects: Array = TypedVariant.as_array(meta.get("effects", []))
	var ops: PackedStringArray = PackedStringArray()
	for e_v: Variant in effects:
		var e: Dictionary = TypedVariant.as_dict(e_v)
		ops.append(str(e.get("op", "")))
	out[0] = TypedVariant.as_float(meta.get("cost", 0.0), 0.0) / 20.0
	var si: int = SIZES.find(sz)
	if si >= 0:
		out[1 + si] = 1.0
	var cat: String = str(meta.get("shop_category", ""))
	var repair: bool = cat == "repair"
	for op: String in ops:
		if op.contains("repair") or op.contains("Repair"):
			repair = true
		if op.contains("mul"):
			out[6] = 1.0
	out[5] = 1.0 if repair else 0.0
	out[7] = 1.0 if TypedVariant.as_bool(meta.get("implant", false), false) else 0.0
	out[8] = float(ops.size()) / 6.0
	out[9] = 1.0
	out[10] = 1.0
	return out


static func flatten_cell(x: int, z: int) -> int:
	var idx: int = 0
	for zz: int in range(maxi(0, z)):
		idx += BoardController.field_cols_at(zz)
	idx += maxi(0, x)
	return clampi(idx, 0, MAX_CELLS - 1)


static func _ops_intent(policy: OnnxCpuPolicy, ctx: Dictionary) -> PackedFloat32Array:
	var intent: PackedFloat32Array = PackedFloat32Array()
	intent.resize(D_DIM)
	if policy == null or not policy.nets_ready():
		return intent
	var ops: PackedFloat32Array = encode_ops(ctx)
	var mg: PackedFloat32Array = PackedFloat32Array()
	mg.resize(MG_DIM)
	mg[0] = TypedVariant.as_float(ctx.get("gold", 0), 0.0) / 50.0
	mg[1] = TypedVariant.as_float(ctx.get("level", 1), 1.0) / 20.0
	mg[2] = TypedVariant.as_float(ctx.get("round", 1), 1.0) / 20.0
	var g: PackedFloat32Array = policy.infer_logits("match_global", mg)
	if g.size() < D_DIM:
		g.resize(D_DIM)
	var ops_in: PackedFloat32Array = _concat3(ops, g, PackedFloat32Array())
	var o: PackedFloat32Array = policy.infer_logits("ops", ops_in)
	var n: int = mini(D_DIM, o.size())
	for i: int in range(n):
		intent[i] = o[i]
	return intent


static func _size_of(hull: Dictionary) -> String:
	if TypedVariant.as_bool(hull.get("requires_cyno_entry", false), false):
		return "XL"
	var g: String = str(hull.get("ship_group", "")).to_lower()
	match g:
		"frigate", "destroyer", "fighter":
			return "S"
		"cruiser", "battlecruiser":
			return "M"
		"battleship":
			return "L"
		"dreadnought", "carrier", "force_auxiliary", "supercarrier", "titan", "freighter", "capital":
			return "XL"
		_:
			return "S" if str(hull.get("capital_role", "")) == "" else "XL"


static func _titan_index(titan: String) -> int:
	var i: int = TITANS.find(titan)
	return i if i >= 0 else 1


static func _one_hot(i: int, n: int) -> PackedFloat32Array:
	var v: PackedFloat32Array = PackedFloat32Array()
	v.resize(n)
	if i >= 0 and i < n:
		v[i] = 1.0
	return v


static func _blit(dst: PackedFloat32Array, off: int, src: PackedFloat32Array) -> void:
	var n: int = mini(src.size(), dst.size() - off)
	for i: int in range(maxi(0, n)):
		dst[off + i] = src[i]


static func _concat3(a: PackedFloat32Array, b: PackedFloat32Array, c: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(a.size() + b.size() + c.size())
	var i: int = 0
	for v: float in a:
		out[i] = v
		i += 1
	for v2: float in b:
		out[i] = v2
		i += 1
	for v3: float in c:
		out[i] = v3
		i += 1
	return out


static func _pad_arr(vec: Array[float], n: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var m: int = mini(n, vec.size())
	for i: int in range(m):
		out[i] = vec[i]
	return out
