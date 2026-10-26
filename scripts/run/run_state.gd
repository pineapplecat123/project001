extends Node

const MapGraph = preload("res://scripts/map/map_graph.gd")
const RestConstants = preload("res://scripts/rest/rest_constants.gd")
## 局内 Run 状态：地图 ↔ 战斗之间保持金币 / 弹药袋 / HP / 粉弹成长。
## 非地图练习战不启用本对象（active=false）。

var active: bool = false
var run_seed: int = 0
var gold: int = 0
var bag: Array[int] = []
var player_hp: int = CombatConstants.PLAYER_MAX_HP
var player_max_hp: int = CombatConstants.PLAYER_MAX_HP
var pink_bonus: int = 0

var graph: Dictionary = {}
var current_node_id: int = 0
var completed_ids: Array[int] = []
## 进入战斗前写入；胜利回地图后清零。
var pending_combat_node_id: int = -1
## 商店打开中写入；离开商店后清零并完成节点。
var pending_shop_node_id: int = -1
## 休息打开中写入；确认回血或离开后清零并完成节点。
var pending_rest_node_id: int = -1
var run_finished: bool = false
var last_message: String = ""
## 主菜单「无限模式」进入战斗时置 true；战斗读取后清零。
var pending_endless: bool = false
## 地图 run 所选罪孽弹 id；begin_run 时灌入 10+5。
var selected_sin_ammo_id: int = 16


func is_in_map_run() -> bool:
	return active


func request_endless_combat() -> void:
	## 主菜单无限模式：退出地图 run，标记下一场战斗为无限。
	end_run()
	pending_endless = true


func request_practice_combat() -> void:
	end_run()
	pending_endless = false


func consume_pending_endless() -> bool:
	var v := pending_endless
	pending_endless = false
	return v



func begin_run(seed_value: int = 0, force_placeholder_kind: String = "") -> void:
	active = true
	run_finished = false
	last_message = ""
	if seed_value != 0:
		run_seed = seed_value
	else:
		run_seed = randi()
	gold = 0
	bag.clear()
	_fill_run_starter_bag()
	player_max_hp = CombatConstants.PLAYER_MAX_HP
	player_hp = player_max_hp
	pink_bonus = 0
	graph = MapGraph.build_mini(run_seed, force_placeholder_kind)
	current_node_id = 0
	completed_ids = [0]
	pending_combat_node_id = -1
	pending_shop_node_id = -1
	pending_rest_node_id = -1
	pending_endless = false


func end_run() -> void:
	active = false
	pending_endless = false
	pending_combat_node_id = -1
	pending_shop_node_id = -1
	pending_rest_node_id = -1
	run_finished = false
	last_message = ""
	graph = {}
	completed_ids.clear()
	bag.clear()
	gold = 0
	pink_bonus = 0


func available_node_ids() -> Array[int]:
	var out: Array[int] = []
	if not active or run_finished:
		return out
	for nid in MapGraph.neighbors(graph, current_node_id):
		if not completed_ids.has(nid):
			out.append(nid)
	return out


func is_completed(node_id: int) -> bool:
	return completed_ids.has(node_id)


func enter_combat_node(node_id: int) -> bool:
	if not active or run_finished:
		return false
	if not available_node_ids().has(node_id):
		return false
	var n: Dictionary = MapGraph.node_by_id(graph, node_id)
	if not MapGraph.is_combat_like(n):
		return false
	pending_combat_node_id = node_id
	return true


## 进入商店节点：不立刻完成；离开后再标完成。
func enter_shop_node(node_id: int) -> bool:
	if not active or run_finished:
		return false
	if pending_shop_node_id >= 0:
		return false
	if not available_node_ids().has(node_id):
		return false
	var n: Dictionary = MapGraph.node_by_id(graph, node_id)
	if not MapGraph.is_shop_node(n):
		return false
	pending_shop_node_id = node_id
	return true


## 离开商店：写回金币/袋，完成节点，清除 pending（移除费用由 ShopState 会话重置）。
func leave_shop(payload: Dictionary) -> String:
	if not active:
		return "局未开始"
	var node_id: int = pending_shop_node_id
	if node_id < 0:
		return "未在商店中"
	if payload.has("gold"):
		gold = int(payload["gold"])
	if payload.has("bag"):
		bag = _copy_int_array(payload["bag"])
	pending_shop_node_id = -1
	_complete_node(node_id)
	last_message = "离开商店，可选择下一节点。"
	return last_message


## 进入休息节点：不立刻完成；确认回血或离开后再标完成。
func enter_rest_node(node_id: int) -> bool:
	if not active or run_finished:
		return false
	if pending_rest_node_id >= 0:
		return false
	if not available_node_ids().has(node_id):
		return false
	var n: Dictionary = MapGraph.node_by_id(graph, node_id)
	if not MapGraph.is_rest_node(n):
		return false
	pending_rest_node_id = node_id
	return true


## 确认回血：按灰盒比例恢复 HP（不超 max），袋/金不变，完成节点。
func confirm_rest_heal() -> String:
	if not active:
		return "局未开始"
	var node_id: int = pending_rest_node_id
	if node_id < 0:
		return "未在休息中"
	var amount: int = RestConstants.heal_amount(player_max_hp)
	var before: int = player_hp
	player_hp = mini(player_max_hp, player_hp + amount)
	var gained: int = player_hp - before
	pending_rest_node_id = -1
	_complete_node(node_id)
	last_message = "休息恢复 %d HP（%d→%d / %d）。袋与金币不变。" % [
		gained, before, player_hp, player_max_hp
	]
	return last_message


## 离开休息（不回血）：完成节点，袋/金/HP 不变。
func leave_rest() -> String:
	if not active:
		return "局未开始"
	var node_id: int = pending_rest_node_id
	if node_id < 0:
		return "未在休息中"
	pending_rest_node_id = -1
	_complete_node(node_id)
	last_message = "离开休息点（未回血），可选择下一节点。"
	return last_message


## 访问非商店/非休息占位（特殊事件）：灰盒未开放，路过。
func visit_placeholder(node_id: int) -> String:
	if not active or run_finished:
		return "局未开始"
	if not available_node_ids().has(node_id):
		return "该节点不可达"
	var n: Dictionary = MapGraph.node_by_id(graph, node_id)
	if int(n.get("type", -1)) != MapGraph.NodeType.PLACEHOLDER:
		return "不是占位节点"
	if MapGraph.is_shop_node(n):
		return "商店节点请进入商店"
	if MapGraph.is_rest_node(n):
		return "休息节点请进入休息"
	var kind: String = str(n.get("kind", n.get("label", "非战斗")))
	_complete_node(node_id)
	last_message = "【%s】灰盒未开放：已路过，无奖励。" % kind
	return last_message


func apply_combat_result(payload: Dictionary, victory: bool) -> void:
	if not active:
		return
	# 无论胜负，同步战斗内资源（失败也保留当前状态供展示，随后 end）
	if payload.has("gold"):
		gold = int(payload["gold"])
	if payload.has("bag"):
		bag = _copy_int_array(payload["bag"])
	if payload.has("player_hp"):
		player_hp = int(payload["player_hp"])
	if payload.has("player_max_hp"):
		player_max_hp = int(payload["player_max_hp"])
	if payload.has("pink_bonus"):
		pink_bonus = int(payload["pink_bonus"])
	var node_id: int = pending_combat_node_id
	pending_combat_node_id = -1
	if not victory:
		last_message = "战斗失败，本局结束。"
		run_finished = true
		return
	if node_id < 0:
		return
	_complete_node(node_id)
	var n: Dictionary = MapGraph.node_by_id(graph, node_id)
	if int(n.get("type", -1)) == MapGraph.NodeType.FINALE:
		run_finished = true
		last_message = "Boss 终战胜利！缩小版地图通关。金币 %d · 袋内 %d 发。" % [gold, bag.size()]
	elif MapGraph.is_elite_node(n):
		last_message = "精英战胜利，可选择下一节点。"
	else:
		last_message = "战斗胜利，可选择下一节点。"


func combat_snapshot() -> Dictionary:
	return {
		"gold": gold,
		"bag": bag.duplicate(),
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"pink_bonus": pink_bonus,
		"seed": run_seed,
		"from_map": true,
		"node_id": pending_combat_node_id,
		"encounter": encounter_for_node(pending_combat_node_id),
	}


## normal / elite / boss（灰盒；由地图节点类型决定）
func encounter_for_node(node_id: int) -> String:
	var n: Dictionary = MapGraph.node_by_id(graph, node_id)
	if MapGraph.is_elite_node(n):
		return "elite"
	if MapGraph.is_boss_node(n):
		return "boss"
	return "normal"


func _complete_node(node_id: int) -> void:
	if not completed_ids.has(node_id):
		completed_ids.append(node_id)
	current_node_id = node_id


func _copy_int_array(src) -> Array[int]:
	var out: Array[int] = []
	for x in src:
		out.append(int(x))
	return out


func set_selected_sin(sin_ammo_id: int) -> void:
	if sin_ammo_id not in [16, 17, 18]:
		sin_ammo_id = 16
	selected_sin_ammo_id = sin_ammo_id


func _fill_run_starter_bag() -> void:
	bag.clear()
	for _i in CombatConstants.STARTER_WHITE_COUNT:
		bag.append(CombatConstants.WHITE_AMMO_ID)
	for _i in CombatConstants.STARTER_SIN_COUNT:
		bag.append(selected_sin_ammo_id)
