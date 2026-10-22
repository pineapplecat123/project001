class_name EnemyInstance
## 场上敌人运行时实例。

var def_id: int = 0
var name_zh: String = ""
var max_hp: int = 0
var hp: int = 0
var atk: int = 0
var mobility: int = 1
var tags: Array[String] = []
var cell: int = CombatConstants.BOARD_SIZE - 1
var bleed_stacks: int = 0  ## stub：本模块不结算


func _init(def: Dictionary = {}, spawn_cell: int = CombatConstants.BOARD_SIZE - 1) -> void:
	if def.is_empty():
		return
	def_id = int(def.get("id", 0))
	name_zh = str(def.get("name", ""))
	max_hp = int(def.get("hp", 1))
	hp = max_hp
	atk = int(def.get("atk", 1))
	mobility = int(def.get("mobility", 1))
	tags.clear()
	for t in def.get("tags", []):
		tags.append(str(t))
	cell = spawn_cell
	bleed_stacks = 0


func is_alive() -> bool:
	return hp > 0


func has_tag(tag: String) -> bool:
	return tag in tags


## 应用命中；返回实际扣血。石头 <4 无视。生物流血本模块仅 +stack 不结算。
func apply_hit(raw_damage: int) -> int:
	if not is_alive():
		return 0
	var dmg := raw_damage
	if has_tag("石头") and dmg < 4:
		dmg = 0
	if dmg <= 0:
		return 0
	hp = maxi(0, hp - dmg)
	if has_tag("生物") and not has_tag("骷髅"):
		bleed_stacks += 1
	return dmg
