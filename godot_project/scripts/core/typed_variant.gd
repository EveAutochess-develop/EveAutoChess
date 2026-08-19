extends RefCounted
class_name TypedVariant
## Safe narrowing for Dictionary.get / JSON Variant values.
## Use only at dynamic boundaries — do not change call-site semantics.


static func as_bool(v: Variant, default_val: bool = false) -> bool:
	match typeof(v):
		TYPE_BOOL:
			@warning_ignore("unsafe_cast")
			return v as bool
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return (v as int) != 0
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return (v as float) != 0.0
		TYPE_STRING:
			var s: String = str(v)
			return s == "true" or s == "1"
		_:
			return default_val


static func as_int(v: Variant, default_val: int = 0) -> int:
	match typeof(v):
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return v as int
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return int(v as float)
		TYPE_BOOL:
			@warning_ignore("unsafe_cast")
			return 1 if (v as bool) else 0
		TYPE_STRING:
			return str(v).to_int()
		_:
			return default_val


static func as_float(v: Variant, default_val: float = 0.0) -> float:
	match typeof(v):
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return v as float
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return float(v as int)
		TYPE_BOOL:
			@warning_ignore("unsafe_cast")
			return 1.0 if (v as bool) else 0.0
		TYPE_STRING:
			return str(v).to_float()
		_:
			return default_val


static func as_vector3(v: Variant, default_val: Vector3 = Vector3.ZERO) -> Vector3:
	if typeof(v) != TYPE_VECTOR3:
		return default_val
	@warning_ignore("unsafe_cast")
	return v as Vector3


static func as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		@warning_ignore("unsafe_cast")
		return v as Dictionary
	return {}


static func as_array(v: Variant) -> Array:
	if v is Array:
		@warning_ignore("unsafe_cast")
		return v as Array
	## Packed*Array is not `Array`; WeaponSfxCatalog and similar bakers use PSA.
	if v is PackedStringArray:
		@warning_ignore("unsafe_cast")
		var psa: PackedStringArray = v as PackedStringArray
		var out_s: Array = []
		out_s.resize(psa.size())
		for i: int in range(psa.size()):
			out_s[i] = psa[i]
		return out_s
	if v is PackedInt32Array:
		@warning_ignore("unsafe_cast")
		var pia: PackedInt32Array = v as PackedInt32Array
		var out_i: Array = []
		out_i.resize(pia.size())
		for i2: int in range(pia.size()):
			out_i[i2] = pia[i2]
		return out_i
	if v is PackedFloat32Array:
		@warning_ignore("unsafe_cast")
		var pfa: PackedFloat32Array = v as PackedFloat32Array
		var out_f: Array = []
		out_f.resize(pfa.size())
		for i3: int in range(pfa.size()):
			out_f[i3] = pfa[i3]
		return out_f
	return []


static func as_packed_f32(v: Variant) -> PackedFloat32Array:
	if v is PackedFloat32Array:
		@warning_ignore("unsafe_cast")
		return v as PackedFloat32Array
	return PackedFloat32Array()


static func as_packed_bytes(v: Variant) -> PackedByteArray:
	if v is PackedByteArray:
		@warning_ignore("unsafe_cast")
		return v as PackedByteArray
	return PackedByteArray()
