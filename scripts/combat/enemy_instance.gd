class_name EnemyInstance
## 场上敌人运行时实例（汽油/燃烧/湿/流血）。

var def_id: int = 0
var name_zh: String = ""
var max_hp: int = 0
var hp: int = 0
var atk: int = 0
var mobility: int = 1
var tags: Array[String] = []
var cell: int = CombatConstants.BOARD_SIZE - 1
var bleed_stacks: int = 0
var gas_stacks: int = 0
var burn_stacks: int = 0
var wet_stacks: int = 0
## 攻击距离（格）；1=仅邻接。精英/Boss 灰盒可抬高。
var attack_range: int = 1


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
	gas_stacks = 0
	burn_stacks = 0
	wet_stacks = 0
	attack_range = 1


func is_alive() -> bool:
	return hp > 0


func has_tag(tag: String) -> bool:
	return tag in tags


## 纯扣血（石头 <4 无视）。不触发击中特效。
func apply_damage(raw_damage: int) -> int:
	if not is_alive():
		return 0
	var dmg := raw_damage
	if has_tag("石头") and dmg < 4:
		dmg = 0
	if dmg <= 0:
		return 0
	hp = maxi(0, hp - dmg)
	return dmg


## 子弹/攻击命中：扣血 + 生物流血叠层（骷髅不流血）。
func apply_hit(raw_damage: int) -> int:
	var dealt := apply_damage(raw_damage)
	if dealt > 0 and has_tag("生物") and not has_tag("骷髅"):
		bleed_stacks += 1
	return dealt


func status_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if gas_stacks > 0:
		parts.append("油%d" % gas_stacks)
	if burn_stacks > 0:
		parts.append("燃%d" % burn_stacks)
	if wet_stacks > 0:
		parts.append("湿%d" % wet_stacks)
	if bleed_stacks > 0:
		parts.append("血%d" % bleed_stacks)
	return " ".join(parts)
