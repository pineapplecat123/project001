extends GutTest

const MapGraph = preload("res://scripts/map/map_graph.gd")
const RestConstants = preload("res://scripts/rest/rest_constants.gd")
## 休息灰盒：回血比例、封顶、袋金不变、进入/离开完成节点。


func before_each() -> void:
	DataRegistry.reload()
	RunState.end_run()


func test_heal_amount_is_percent_of_max() -> void:
	var amt := RestConstants.heal_amount(20)
	assert_eq(amt, 6)  # ceil(20 * 30%) = 6
	assert_eq(RestConstants.HEAL_PERCENT, 30)
	assert_eq(RestConstants.heal_amount(10), 3)
	assert_eq(RestConstants.heal_amount(0), 0)


func test_rest_heal_caps_at_max_and_keeps_bag_gold() -> void:
	RunState.begin_run(21, MapGraph.KIND_REST)
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result({
		"gold": 33,
		"bag": RunState.bag.duplicate(),
		"player_hp": 10,
		"player_max_hp": CombatConstants.PLAYER_MAX_HP,
		"pink_bonus": 0,
	}, true)
	var bag_before := RunState.bag.duplicate()
	assert_true(RunState.available_node_ids().has(3))
	assert_true(MapGraph.is_rest_node(MapGraph.node_by_id(RunState.graph, 3)))
	assert_true(RunState.enter_rest_node(3))
	assert_eq(RunState.pending_rest_node_id, 3)
	assert_false(RunState.is_completed(3))
	var msg := RunState.confirm_rest_heal()
	assert_string_contains(msg, "休息恢复")
	assert_eq(RunState.player_hp, 16)  # 10 + 6
	assert_eq(RunState.gold, 33)
	assert_eq(RunState.bag, bag_before)
	assert_eq(RunState.pending_rest_node_id, -1)
	assert_true(RunState.is_completed(3))
	assert_eq(RunState.current_node_id, 3)
	assert_true(RunState.available_node_ids().has(4))


func test_rest_heal_does_not_exceed_max() -> void:
	RunState.begin_run(22, MapGraph.KIND_REST)
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result({
		"gold": 1,
		"bag": RunState.bag.duplicate(),
		"player_hp": 18,
		"player_max_hp": 20,
		"pink_bonus": 0,
	}, true)
	assert_true(RunState.enter_rest_node(3))
	RunState.confirm_rest_heal()
	assert_eq(RunState.player_hp, 20)


func test_leave_rest_without_heal() -> void:
	RunState.begin_run(23, MapGraph.KIND_REST)
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result({
		"gold": 7,
		"bag": RunState.bag.duplicate(),
		"player_hp": 11,
		"player_max_hp": 20,
		"pink_bonus": 0,
	}, true)
	var bag_before := RunState.bag.size()
	assert_true(RunState.enter_rest_node(3))
	var msg := RunState.leave_rest()
	assert_string_contains(msg, "未回血")
	assert_eq(RunState.player_hp, 11)
	assert_eq(RunState.gold, 7)
	assert_eq(RunState.bag.size(), bag_before)
	assert_true(RunState.is_completed(3))
	assert_eq(RunState.pending_rest_node_id, -1)


func test_visit_placeholder_rejects_rest() -> void:
	RunState.begin_run(24, MapGraph.KIND_REST)
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result({
		"gold": 0,
		"bag": RunState.bag.duplicate(),
		"player_hp": 20,
		"player_max_hp": 20,
		"pink_bonus": 0,
	}, true)
	var msg := RunState.visit_placeholder(3)
	assert_string_contains(msg, "休息")
	assert_false(RunState.is_completed(3))
