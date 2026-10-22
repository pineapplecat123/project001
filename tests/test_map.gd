extends GutTest

const MapGraph = preload("res://scripts/map/map_graph.gd")
## 缩小版地图：图结构、可达性、占位路过、战斗进出保持袋/金。


func before_each() -> void:
	DataRegistry.reload()
	RunState.end_run()


func test_mini_graph_has_combat_and_placeholder() -> void:
	var g := MapGraph.build_mini(42)
	var types := {}
	for n in g["nodes"]:
		types[int(n["type"])] = int(types.get(int(n["type"]), 0)) + 1
	assert_eq(int(types.get(MapGraph.NodeType.START, 0)), 1)
	assert_gte(int(types.get(MapGraph.NodeType.COMBAT, 0)), 2)
	assert_eq(int(types.get(MapGraph.NodeType.PLACEHOLDER, 0)), 1)
	assert_eq(int(types.get(MapGraph.NodeType.FINALE, 0)), 1)
	assert_eq(int(types.get(MapGraph.NodeType.ELITE, 0)), 1)
	assert_eq(g["edges"].size(), 6)
	var ph := {}
	for n in g["nodes"]:
		if int(n["type"]) == MapGraph.NodeType.PLACEHOLDER:
			ph = n
			break
	assert_true(MapGraph.PLACEHOLDER_KINDS.has(str(ph.get("kind", ""))))


func test_run_begin_available_are_first_branch() -> void:
	RunState.begin_run(7)
	assert_true(RunState.active)
	assert_eq(RunState.current_node_id, 0)
	var avail := RunState.available_node_ids()
	assert_eq(avail.size(), 2)
	assert_true(avail.has(1))
	assert_true(avail.has(2))
	assert_eq(RunState.bag.size(), CombatConstants.STARTER_WHITE_COUNT)
	assert_eq(RunState.gold, 0)


func test_placeholder_visit_advances_without_reward() -> void:
	RunState.begin_run(3, "特殊事件")
	# 必须先打完一条战斗支线才能到占位；直接伪造位置测 visit API：
	# 从起点只能到 1/2。先完成节点 1。
	assert_true(RunState.enter_combat_node(1))
	assert_eq(RunState.pending_combat_node_id, 1)
	# 模拟战斗胜利回写
	var payload := {
		"gold": 15,
		"bag": RunState.bag.duplicate(),
		"player_hp": 18,
		"player_max_hp": CombatConstants.PLAYER_MAX_HP,
		"pink_bonus": 0,
	}
	payload["bag"].append(CombatConstants.WHITE_AMMO_ID)
	RunState.apply_combat_result(payload, true)
	assert_eq(RunState.current_node_id, 1)
	assert_eq(RunState.gold, 15)
	assert_eq(RunState.player_hp, 18)
	assert_true(RunState.available_node_ids().has(3))
	var bag_before := RunState.bag.size()
	var msg := RunState.visit_placeholder(3)
	assert_string_contains(msg, "灰盒未开放")
	assert_eq(RunState.current_node_id, 3)
	assert_eq(RunState.bag.size(), bag_before)
	assert_eq(RunState.gold, 15)
	assert_true(RunState.available_node_ids().has(4))


func test_combat_start_from_run_keeps_bag_gold() -> void:
	RunState.begin_run(9)
	RunState.gold = 42
	RunState.bag.clear()
	for _i in 5:
		RunState.bag.append(CombatConstants.WHITE_AMMO_ID)
	RunState.player_hp = 17
	RunState.pink_bonus = 2
	assert_true(RunState.enter_combat_node(1))
	var cs := CombatState.new(9)
	cs.start_from_run(RunState.combat_snapshot(), 9)
	assert_true(cs.from_map_run)
	assert_eq(cs.gold, 42)
	assert_eq(cs.bag.size(), 5)
	assert_eq(cs.player_hp, 17)
	assert_eq(cs.pink_bonus, 2)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	assert_gt(cs.alive_enemies().size(), 0)


func test_export_run_payload_merges_discard() -> void:
	var cs := CombatState.new(5)
	cs.start_from_run({
		"gold": 10,
		"bag": [1, 1, 1],
		"player_hp": 20,
		"player_max_hp": 20,
		"pink_bonus": 0,
		"seed": 5,
	}, 5)
	cs.discard.append(1)
	cs.discard.append(1)
	var payload := cs.export_run_payload()
	assert_eq(int(payload["gold"]), 10)
	assert_eq(payload["bag"].size(), 5)
	assert_eq(cs.discard.size(), 0)


func test_finale_victory_finishes_run() -> void:
	RunState.begin_run(11, "特殊事件")
	# 路径：0 → 1(战斗) → 3(占位·非商店) → 4(精英) → 5(终战 Boss)
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result(_snap(10), true)
	assert_eq(RunState.current_node_id, 1)
	var msg := RunState.visit_placeholder(3)
	assert_string_contains(msg, "灰盒未开放")
	assert_eq(RunState.current_node_id, 3)
	assert_true(RunState.enter_combat_node(4))
	RunState.apply_combat_result(_snap(20), true)
	assert_eq(RunState.current_node_id, 4)
	assert_true(RunState.available_node_ids().has(5))
	assert_true(RunState.enter_combat_node(5))
	RunState.apply_combat_result(_snap(99, 12), true)
	assert_true(RunState.run_finished)
	assert_eq(RunState.gold, 99)
	assert_string_contains(RunState.last_message, "通关")


func _snap(gold: int, hp: int = -1) -> Dictionary:
	return {
		"gold": gold,
		"bag": RunState.bag.duplicate(),
		"player_hp": RunState.player_hp if hp < 0 else hp,
		"player_max_hp": RunState.player_max_hp,
		"pink_bonus": RunState.pink_bonus,
	}
