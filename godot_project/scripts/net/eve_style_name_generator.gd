extends RefCounted
class_name EveStyleNameGenerator
## EVE PC–style account names (TopDog EveStyleNameGenerator syllable tables).
## Used for AI seat nicks (MULTIPLAYER_MATCH_FLOW §2.1).

const FIRST: Array[String] = [
	"Hakodan", "Suolen", "Arkan", "Breia", "Chande", "Duon", "Eifyr", "Friban",
	"Galm", "Helen", "Iiris", "Jandice", "Kador", "Lai", "Merol", "Nakam",
	"Olo", "Perrin", "Quafe", "Roden", "Sais", "Tash", "Uri", "Vilam",
	"Warr", "Yani", "Zainou", "Cal", "Dar", "Hel", "Jas", "Kal", "Mer", "Nav",
	"Sol", "Tor", "Vel", "Zek",
]

const LAST: Array[String] = [
	"Ishukori", "Malait", "Tendren", "Vilamoen", "Erkinen", "Saissore", "Duvolle",
	"Kaunokka", "Seitu", "Tash-Murkon", "Korako", "Sarpati", "Mordok", "Vherok",
	"ion", "ius", "eth", "dan", "tor", "vek", "mon", "kin", "ara", "oth",
]

const MID: Array[String] = [
	"aen", "ain", "ara", "eis", "ian", "ius", "ora", "uen", "eth", "oth", "el",
	"or", "an", "en",
]


static func roll(rng: RandomNumberGenerator = null) -> String:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var style: int = r.randi_range(0, 99)
	if style < 40:
		return _pick(FIRST, r) + " " + _pick(LAST, r)
	if style < 70:
		var bas: String = _pick(FIRST, r)
		var take: int = mini(4, bas.length())
		var head: String = bas.substr(0, take)
		if head.length() > 0:
			head = head.substr(0, 1).to_upper() + head.substr(1)
		return head + _pick(MID, r) + _pick(LAST, r)
	return _pick(FIRST, r) + "-" + str(1000 + r.randi_range(0, 8999))


static func _pick(pool: Array[String], rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return "Pilot"
	return pool[rng.randi_range(0, pool.size() - 1)]
