extends RefCounted
class_name WeaponSfxCatalog
## Baked weapon SFX paths (COMBAT §8.1). Regenerated when wav set changes.

static func pools() -> Dictionary:
	var d: Dictionary = {}
	d["hybrid/large"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/hybrid/large/101472002_EVE_-_Rail_Turret_Extra_Large_-_CLOSE_-_Last_Shot_Tail_05.wav",
		"res://assets/audio/weapon_sfx/hybrid/large/1028621272_EVE_-_Rail_Turret_Extra_Large_-_CLOSE_-_First_Shot_05.wav",
		"res://assets/audio/weapon_sfx/hybrid/large/1052079357_EVE_-_Hybrid_Extra_Large_Turret_-_CLOSE_-_Last_Shot_03.wav",
		"res://assets/audio/weapon_sfx/hybrid/large/1052793791_EVE_-_Hybrid_Extra_Large_Turret_-_CLOSE_-_Last_Shot_Tail_01.wav",
	])
	d["hybrid/medium"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/hybrid/medium/1039160754_EVE_-_Hybrid_Medium_Turret_-_CLOSE_-_First_Shot_Body_04.wav",
		"res://assets/audio/weapon_sfx/hybrid/medium/199982075_EVE_-_Hybrid_Medium_Turret_-_CLOSE_-_First_Shot_Body_03.wav",
		"res://assets/audio/weapon_sfx/hybrid/medium/242933668_EVE_-_Hybrid_Medium_Turret_-_CLOSE_-_Last_Shot_Body_02.wav",
		"res://assets/audio/weapon_sfx/hybrid/medium/302762_EVE_-_Hybrid_Medium_Turret_-_CLOSE_-_Last_Shot_Body_01.wav",
	])
	d["hybrid/small"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/hybrid/small/100133725_EVE_-_Hybrid_Small_Turret_-_CLOSE_-_First_Shot_High_Crack_04.wav",
		"res://assets/audio/weapon_sfx/hybrid/small/1005768354_EVE_-_Rail_Turret_Small_-_CLOSE_-_Last_Shot_High_Zap_01.wav",
		"res://assets/audio/weapon_sfx/hybrid/small/1018317553_EVE_-_Rail_Turret_Small_-_CLOSE_-_Last_Shot_High_Zap_03.wav",
		"res://assets/audio/weapon_sfx/hybrid/small/1035891253_EVE_-_Hybrid_Small_Turret_-_CLOSE_-_Fire_02.wav",
	])
	d["hybrid/unk"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/hybrid/unk/118875461_EVE_-_Hybrid_Blast_Impact_Standard_Near_08.wav",
		"res://assets/audio/weapon_sfx/hybrid/unk/1268900_EVE_-_Hybrid_Blast_Impact_Standard_Near_01.wav",
		"res://assets/audio/weapon_sfx/hybrid/unk/197056390_EVE_-_Hybrid_Blast_Impact_Standard_Far_04.wav",
		"res://assets/audio/weapon_sfx/hybrid/unk/228640359_EVE_-_Hybrid_Blast_Impact_Standard_Far_08.wav",
	])
	d["laser/large"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/laser/large/1000872832_EVE_-_Pulse_Large_Turret_-_CLOSE_-_Last_Shot_Tail_Metal_02.wav",
		"res://assets/audio/weapon_sfx/laser/large/1001486364_EVE_-_Beam_Large_Turret_-_CLOSE_-_First_Shot_02.wav",
		"res://assets/audio/weapon_sfx/laser/large/1021994492_EVE_-_Pulse_Extra_Large_Turret_-_CLOSE_-_Last_Shot_Tail_01.wav",
		"res://assets/audio/weapon_sfx/laser/large/1030899832_EVE_-_Beam_Extra_Large_Turret_-_CLOSE_-_First_Shot_02.wav",
	])
	d["laser/medium"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/laser/medium/1022453122_EVE_-_Pulse_Medium_Turret_-_CLOSE_-_Last_Shot_Body_01.wav",
		"res://assets/audio/weapon_sfx/laser/medium/45092686_EVE_-_Pulse_Medium_Turret_-_CLOSE_-_Last_Shot_Body_02.wav",
		"res://assets/audio/weapon_sfx/laser/medium/550487886_EVE_-_Pulse_Medium_Turret_-_CLOSE_-_Last_Shot_Body_04.wav",
		"res://assets/audio/weapon_sfx/laser/medium/729335755_EVE_-_Pulse_Medium_Turret_-_CLOSE_-_Last_Shot_Body_03.wav",
	])
	d["laser/small"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/laser/small/1029014029_EVE_-_Beam_Small_Turret_-_CLOSE_-_Fire_01.wav",
		"res://assets/audio/weapon_sfx/laser/small/1031620089_EVE_-_Pulse_Small_Turret_-_CLOSE_-_Last_Shot_Tail_04.wav",
		"res://assets/audio/weapon_sfx/laser/small/1041671434_EVE_-_Pulse_Small_Turret_-_CLOSE_-_Fire_05.wav",
		"res://assets/audio/weapon_sfx/laser/small/1049392444_EVE_-_Pulse_Small_Turret_-_CLOSE_-_Last_Shot_Tail_03.wav",
	])
	d["laser/unk"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/laser/unk/1030500503_black-laser.wav",
		"res://assets/audio/weapon_sfx/laser/unk/113964752_indicator_beam_activation.wav",
		"res://assets/audio/weapon_sfx/laser/unk/182843022_damage_beam_end.wav",
		"res://assets/audio/weapon_sfx/laser/unk/200040170_damage_beam_start.wav",
	])
	d["laser/xlarge"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/laser/xlarge/302920486_structure_energy_neutralizer_lxl.wav",
	])
	d["missile/capital"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/missile/capital/133032675_antisubcapitalmissile_impact.wav",
		"res://assets/audio/weapon_sfx/missile/capital/528785446_anticapitalmissile_impact.wav",
	])
	d["missile/unk"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/missile/unk/1037971429_missile-outburst-render6.wav",
		"res://assets/audio/weapon_sfx/missile/unk/1052330549_missile-outburst-heavy-rapid1.wav",
		"res://assets/audio/weapon_sfx/missile/unk/428248366_missile-outburst-render4.wav",
		"res://assets/audio/weapon_sfx/missile/unk/492305131_missile-outburst-render5.wav",
	])
	d["projectile/large"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/projectile/large/1009186561_ArtilleryOutburstLarge_Close_BodySweetener_03.wav",
		"res://assets/audio/weapon_sfx/projectile/large/1069487242_ArtilleryOutburstXLarge_CLose_Body_02.wav",
		"res://assets/audio/weapon_sfx/projectile/large/175589791_ArtilleryOutburstLarge_Close_Body_03.wav",
		"res://assets/audio/weapon_sfx/projectile/large/195759928_ArtilleryOutburstXLarge_CLose_Body_01.wav",
	])
	d["projectile/medium"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/projectile/medium/463383052_ArtilleryOutburstMedium_Close_Body_05.wav",
		"res://assets/audio/weapon_sfx/projectile/medium/54582179_ArtilleryOutburstMedium_Close_Body_02.wav",
		"res://assets/audio/weapon_sfx/projectile/medium/578646657_ArtilleryOutburstMedium_Close_Body_04.wav",
		"res://assets/audio/weapon_sfx/projectile/medium/72762490_ArtilleryOutburstMedium_Close_Body_03.wav",
	])
	d["projectile/small"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/projectile/small/1007429549_ArtilleryOutburstSmall_Close_Body_02.wav",
		"res://assets/audio/weapon_sfx/projectile/small/1010552042_ArtilleryOutburstSmall_Close_BodySweetener_05.wav",
		"res://assets/audio/weapon_sfx/projectile/small/113679272_ArtilleryOutburstSmall_Close_BodySweetener_02.wav",
		"res://assets/audio/weapon_sfx/projectile/small/144892774_ArtilleryOutburstSmall_Close_BodySweetener_01.wav",
	])
	d["projectile/unk"] = PackedStringArray([
		"res://assets/audio/weapon_sfx/projectile/unk/135065460_SFX_Impact_Artillery_Armor_Close_Explosion_OS_05.wav",
		"res://assets/audio/weapon_sfx/projectile/unk/175375210_SFX_Impact_Artillery_Armor_Close_Attack_OS_09.wav",
		"res://assets/audio/weapon_sfx/projectile/unk/187962475_SFX_Impact_Artillery_Armor_Close_Attack_OS_01.wav",
		"res://assets/audio/weapon_sfx/projectile/unk/22187201_SFX_Impact_Artillery_Armor_Close_Attack_OS_10.wav",
	])
	return d
