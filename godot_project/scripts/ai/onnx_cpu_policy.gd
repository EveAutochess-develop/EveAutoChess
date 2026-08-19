extends RefCounted
class_name OnnxCpuPolicy
## CPU Sequential loader for farm six-net bundles. Ranking fallback when nets missing.

const SCHEMA_VER: String = "1"
const MANIFEST_USER: String = "user://eveac_ai/model_bundle/manifest.json"
const MANIFEST_RES: String = "res://data/ai/model_bundle/manifest.json"

var fallback: WeightDrivenAi = WeightDrivenAi.new()
var model_bundle_hash: String = ""
var onnx_package_present: bool = false
var loaded_manifest_path: String = ""
var _nets: Dictionary = {} ## name -> {W0,b0,W1,b1,W2,b2} row-major PackedFloat32Array + dims
var _net_delta: Dictionary = {} ## overlay from user://eveac_ai/learn_delta
var _infer_ready: bool = false
const W_CLIP: float = 8.0


func try_autoload() -> bool:
	var ok_fallback: bool = fallback.try_autoload()
	onnx_package_present = false
	model_bundle_hash = ""
	loaded_manifest_path = ""
	_infer_ready = false
	_nets.clear()
	_net_delta.clear()
	var manifest_path: String = ""
	if FileAccess.file_exists(MANIFEST_USER):
		manifest_path = MANIFEST_USER
	elif FileAccess.file_exists(MANIFEST_RES):
		manifest_path = MANIFEST_RES
	if manifest_path == "":
		return ok_fallback
	var f: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if f == null:
		return ok_fallback
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return ok_fallback
	var d: Dictionary = TypedVariant.as_dict(parsed)
	if str(d.get("schema_ver", "")) != SCHEMA_VER:
		return ok_fallback
	model_bundle_hash = str(d.get("model_bundle_hash", ""))
	loaded_manifest_path = manifest_path
	var dir: String = manifest_path.get_base_dir()
	var names: PackedStringArray = PackedStringArray(["titan", "match_global", "ops", "shop", "fit", "place"])
	var loaded: int = 0
	for n: String in names:
		var wpath: String = dir.path_join("%s.json" % n)
		if not FileAccess.file_exists(wpath):
			continue
		var wf: FileAccess = FileAccess.open(wpath, FileAccess.READ)
		if wf == null:
			continue
		var wtxt: String = wf.get_as_text()
		wf.close()
		var wv: Variant = JSON.parse_string(wtxt)
		if not (wv is Dictionary):
			continue
		_nets[n] = TypedVariant.as_dict(wv)
		loaded += 1
	onnx_package_present = loaded > 0
	_infer_ready = loaded == names.size()
	InMatchSlowLearn.ensure_loaded()
	set_net_delta(InMatchSlowLearn.net_delta())
	if fallback != null:
		fallback.apply_genome_delta(InMatchSlowLearn.genome_delta())
	return ok_fallback or _infer_ready


func is_ready() -> bool:
	return _infer_ready or (fallback != null and fallback.is_ready())


func nets_ready() -> bool:
	return _infer_ready


func pick_unpurchased_shop_index(shop_slots: Array, titan_id: String) -> int:
	return fallback.pick_unpurchased_shop_index(shop_slots, titan_id)


func current_titan_slice(titan_id: String) -> Dictionary:
	return fallback.current_titan_slice(titan_id)


func stance_mix() -> PackedFloat32Array:
	return fallback.stance_mix()


func ship_tier(ship_id: int) -> int:
	return fallback.ship_tier(ship_id)


func infer_logits(net_name: String, x: PackedFloat32Array) -> PackedFloat32Array:
	if not _nets.has(net_name):
		return PackedFloat32Array()
	var spec: Dictionary = TypedVariant.as_dict(_nets[net_name])
	var dlt: Dictionary = TypedVariant.as_dict(_net_delta.get(net_name, {}))
	return _forward_mlp(spec, x, dlt)


func net_spec(net_name: String) -> Dictionary:
	return TypedVariant.as_dict(_nets.get(net_name, {}))


func set_net_delta(d: Dictionary) -> void:
	_net_delta = d.duplicate(true)


func forward_cache(spec: Dictionary, dlt: Dictionary, x: PackedFloat32Array) -> Dictionary:
	var h1: PackedFloat32Array = _linear(spec, "0", x, dlt)
	var a1: PackedFloat32Array = h1.duplicate()
	_silu_inplace(a1)
	var h2: PackedFloat32Array = _linear(spec, "2", a1, dlt)
	var a2: PackedFloat32Array = h2.duplicate()
	_silu_inplace(a2)
	var logits: PackedFloat32Array = _linear(spec, "4", a2, dlt)
	return {"h1": h1, "a1": a1, "h2": h2, "a2": a2, "logits": logits}


func argmax_logits(logits: PackedFloat32Array) -> int:
	if logits.is_empty():
		return 0
	var best_i: int = 0
	var best_v: float = logits[0]
	for i: int in range(1, logits.size()):
		if logits[i] > best_v:
			best_v = logits[i]
			best_i = i
	return best_i


func pick_lobby_titan_race(census: Dictionary = {}, current: String = "", round_i: int = 2) -> String:
	## Lobby TitanNet matches farm titan_obs: pick+stance+census+current_oh+round2.
	var ids: PackedStringArray = WeightDrivenAi.TITAN_IDS
	var x: PackedFloat32Array = PackedFloat32Array()
	x.resize(21)
	var pick: PackedFloat32Array = PackedFloat32Array()
	var stance: PackedFloat32Array = PackedFloat32Array()
	if fallback != null:
		pick = fallback.titan_pick_vec()
		stance = fallback.stance_mix()
	var n_ids: int = ids.size()
	if pick.size() < n_ids:
		pick.resize(n_ids)
		var prior: float = 1.0 / float(n_ids)
		for i: int in range(n_ids):
			pick[i] = prior
	if stance.size() < n_ids:
		stance.resize(n_ids)
		var sp: float = 1.0 / float(n_ids)
		for i: int in range(n_ids):
			stance[i] = sp
	var n_cen: int = 0
	for t: String in ids:
		n_cen += TypedVariant.as_int(census.get(t, 0), 0)
	var den: float = float(maxi(1, n_cen))
	for i: int in range(n_ids):
		x[i] = pick[i]
		x[5 + i] = stance[i]
		x[10 + i] = float(TypedVariant.as_int(census.get(ids[i], 0), 0)) / den if n_cen > 0 else 0.0
		x[15 + i] = 1.0 if current == ids[i] else 0.0
	x[20] = 1.0 if round_i >= 2 else 0.0
	var logits: PackedFloat32Array = infer_logits("titan", x)
	if logits.size() >= n_ids:
		var idx: int = clampi(argmax_logits(logits), 0, n_ids - 1)
		SessionDiagnostics.log("ai.decide", "net=titan race=%s idx=%d round=%d" % [ids[idx], idx, round_i])
		return ids[idx]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var rnd: String = ids[rng.randi_range(0, n_ids - 1)]
	SessionDiagnostics.log("ai.decide", "net=titan race=%s idx=-1 round=%d via=rng" % [rnd, round_i])
	return rnd


func _forward_mlp(spec: Dictionary, x: PackedFloat32Array, dlt: Dictionary = {}) -> PackedFloat32Array:
	var h1: PackedFloat32Array = _linear(spec, "0", x, dlt)
	_silu_inplace(h1)
	var h2: PackedFloat32Array = _linear(spec, "2", h1, dlt)
	_silu_inplace(h2)
	return _linear(spec, "4", h2, dlt)


func _linear(spec: Dictionary, layer: String, x: PackedFloat32Array, dlt: Dictionary = {}) -> PackedFloat32Array:
	var w_v: Variant = spec.get("W%s" % layer, [])
	var b_v: Variant = spec.get("b%s" % layer, [])
	var rows: int = TypedVariant.as_int(spec.get("out%s" % layer, 0), 0)
	var cols: int = TypedVariant.as_int(spec.get("in%s" % layer, 0), 0)
	if rows <= 0 or cols <= 0:
		return PackedFloat32Array()
	var w: Array = TypedVariant.as_array(w_v)
	var b: Array = TypedVariant.as_array(b_v)
	var dw: PackedFloat32Array = PackedFloat32Array()
	var db: PackedFloat32Array = PackedFloat32Array()
	if not dlt.is_empty():
		dw = TypedVariant.as_packed_f32(dlt.get("W%s" % layer, PackedFloat32Array()))
		db = TypedVariant.as_packed_f32(dlt.get("b%s" % layer, PackedFloat32Array()))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(rows)
	for r: int in range(rows):
		var bias_v: Variant = 0.0
		if r < b.size():
			bias_v = b[r]
		var acc: float = TypedVariant.as_float(bias_v, 0.0)
		if r < db.size():
			acc += db[r]
		acc = clampf(acc, -W_CLIP, W_CLIP)
		var base: int = r * cols
		var n: int = mini(cols, x.size())
		for c: int in range(n):
			var wv_el: Variant = 0.0
			var wi: int = base + c
			if wi < w.size():
				wv_el = w[wi]
			var wsum: float = TypedVariant.as_float(wv_el, 0.0)
			if wi < dw.size():
				wsum += dw[wi]
			acc += clampf(wsum, -W_CLIP, W_CLIP) * x[c]
		out[r] = acc
	return out


func _silu_inplace(v: PackedFloat32Array) -> void:
	for i: int in range(v.size()):
		var x: float = v[i]
		v[i] = x / (1.0 + exp(-x))
