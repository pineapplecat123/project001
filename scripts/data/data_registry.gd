extends Node
## 读取 data/*.json。Autoload：DataRegistry

const AMMO_PATH := "res://data/ammo.json"
const ENEMIES_PATH := "res://data/enemies.json"
const ENEMY_TAGS_PATH := "res://data/enemy_tags.json"

var _ammo_by_id: Dictionary = {}
var _enemies_by_id: Dictionary = {}
var _tags_by_id: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_ammo_by_id = _load_by_int_id(AMMO_PATH)
	_enemies_by_id = _load_by_int_id(ENEMIES_PATH)
	_tags_by_id = _load_by_string_id(ENEMY_TAGS_PATH)


func _read_items(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "missing data file: %s" % path)
	var parsed: Variant = JSON.parse_string(text)
	assert(typeof(parsed) == TYPE_DICTIONARY, "bad json root: %s" % path)
	return parsed.get("items", [])


func _load_by_int_id(path: String) -> Dictionary:
	var into := {}
	for item in _read_items(path):
		into[int(item["id"])] = item
	return into


func _load_by_string_id(path: String) -> Dictionary:
	var into := {}
	for item in _read_items(path):
		into[str(item["id"])] = item
	return into


func get_ammo(ammo_id: int) -> Dictionary:
	return _ammo_by_id.get(ammo_id, {})


func get_enemy(enemy_id: int) -> Dictionary:
	return _enemies_by_id.get(enemy_id, {})


func get_tag(tag_id: String) -> Dictionary:
	return _tags_by_id.get(tag_id, {})


func all_ammo() -> Array:
	return _ammo_by_id.values()


func all_enemies() -> Array:
	return _enemies_by_id.values()


func is_ammo_enabled(ammo_id: int) -> bool:
	return bool(get_ammo(ammo_id).get("enabled_in_combat", false))


func is_enemy_enabled(enemy_id: int) -> bool:
	return bool(get_enemy(enemy_id).get("enabled_in_combat", false))


## 袋内点击详情：名称 / 基础伤害 / 效果（无效弹用本地常量）。
func format_ammo_detail_text(ammo_id: int) -> String:
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		return "名称：%s\n基础伤害：0\n效果：\n%s" % [
			CombatConstants.INVALID_AMMO_NAME,
			CombatConstants.INVALID_AMMO_SPECIAL,
		]
	var def: Dictionary = get_ammo(ammo_id)
	if def.is_empty():
		return "未知弹药 #%d" % ammo_id
	var nm := str(def.get("name", "未知"))
	var mode := str(def.get("base_damage_mode", ""))
	var dmg = def.get("base_damage", null)
	var dmg_s: String
	if dmg == null:
		dmg_s = "（公式/%s，见表效果）" % mode
	else:
		dmg_s = "%s（%s）" % [str(dmg), mode if mode != "" else "fixed"]
	var special := str(def.get("special", "无"))
	var tags = def.get("tags", [])
	var tag_s := "、".join(tags) if tags is Array and tags.size() > 0 else "无"
	return "名称：%s\n基础伤害：%s\n标签：%s\n效果：\n%s" % [nm, dmg_s, tag_s, special]
