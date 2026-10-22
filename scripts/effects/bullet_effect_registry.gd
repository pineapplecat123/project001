class_name BulletEffectRegistry
## 弹药效果注册表。

static var _effects: Dictionary = {}


static func ensure_defaults() -> void:
	if _effects.is_empty():
		register(WhiteBulletEffect.new())


static func register(effect: BulletEffect) -> void:
	_effects[effect.ammo_id()] = effect


static func compute_damage(ammo_id: int, ctx: Dictionary = {}) -> int:
	ensure_defaults()
	var effect: BulletEffect = _effects.get(ammo_id, null)
	if effect != null:
		return effect.compute_damage(ctx)
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	if def.get("base_damage_mode", "fixed") == "fixed" and def.get("base_damage", null) != null:
		return int(def["base_damage"])
	return 0
