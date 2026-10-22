class_name WhiteBulletEffect
extends BulletEffect


func ammo_id() -> int:
	return CombatConstants.WHITE_AMMO_ID


func compute_damage(_ctx: Dictionary) -> int:
	var def: Dictionary = DataRegistry.get_ammo(ammo_id())
	return int(def.get("base_damage", 3))
