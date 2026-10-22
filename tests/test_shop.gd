extends GutTest

const MapGraph = preload("res://scripts/map/map_graph.gd")
const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")
## 商店灰盒：买 / 删 / 递增费用 / 离店重置 / 重随。


func before_each() -> void:
	DataRegistry.reload()
	RunState.end_run()


func test_buy_adds_ammo_and_spends_gold() -> void:
	var shop := ShopState.new()
	shop.begin(50, [CombatConstants.WHITE_AMMO_ID], 3, 11)
	assert_eq(shop.stock.size(), ShopConstants.STOCK_SIZE)
	assert_true(shop.can_buy(0))
	var before_bag := shop.bag.size()
	var ammo_id: int = shop.stock[0]
	assert_true(shop.buy(0))
	assert_eq(shop.gold, 50 - ShopConstants.AMMO_PRICE)
	assert_eq(shop.bag.size(), before_bag + 1)
	assert_eq(shop.bag[shop.bag.size() - 1], ammo_id)
	assert_true(shop.sold[0])
	assert_false(shop.can_buy(0))


func test_remove_cost_escalates_then_resets_on_leave() -> void:
	var shop := ShopState.new()
	var bag: Array[int] = []
	for _i in 4:
		bag.append(CombatConstants.WHITE_AMMO_ID)
	shop.begin(100, bag, 3, 22)
	assert_eq(shop.next_remove_cost(), ShopConstants.REMOVE_BASE_COST)
	assert_true(shop.remove_at(0))
	assert_eq(shop.removes_done, 1)
	assert_eq(shop.gold, 100 - ShopConstants.REMOVE_BASE_COST)
	assert_eq(shop.next_remove_cost(), ShopConstants.REMOVE_BASE_COST + ShopConstants.REMOVE_COST_STEP)
	assert_true(shop.remove_at(0))
	assert_eq(shop.removes_done, 2)
	assert_eq(
		shop.gold,
		100 - ShopConstants.REMOVE_BASE_COST - (ShopConstants.REMOVE_BASE_COST + ShopConstants.REMOVE_COST_STEP)
	)
	var payload := shop.end_session()
	assert_false(shop.open)
	assert_eq(shop.removes_done, 0)
	# 再次进店：移除费用从 10 起
	shop.begin(int(payload["gold"]), payload["bag"], 3, 33)
	assert_eq(shop.next_remove_cost(), ShopConstants.REMOVE_BASE_COST)
	assert_eq(shop.removes_done, 0)


func test_reroll_free_then_paid() -> void:
	var shop := ShopState.new()
	shop.begin(20, [CombatConstants.WHITE_AMMO_ID], 3, 44)
	assert_eq(shop.reroll_cost_now(), 0)
	assert_eq(shop.free_rerolls_left, ShopConstants.FREE_REROLLS)
	var first_stock := shop.stock.duplicate()
	assert_true(shop.reroll())
	assert_eq(shop.free_rerolls_left, ShopConstants.FREE_REROLLS - 1)
	assert_eq(shop.gold, 20)
	assert_eq(shop.reroll_cost_now(), ShopConstants.REROLL_COST)
	assert_true(shop.reroll())
	assert_eq(shop.gold, 20 - ShopConstants.REROLL_COST)
	assert_eq(shop.stock.size(), ShopConstants.STOCK_SIZE)
	# first_stock may equal by chance; just ensure sold flags reset
	for s in shop.sold:
		assert_false(s)
	first_stock = first_stock  # silence unused if identical


func test_map_shop_enter_leave_writes_back() -> void:
	RunState.begin_run(7, MapGraph.KIND_SHOP)
	# 走到节点 3：先打完战斗 1
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result({
		"gold": 40,
		"bag": RunState.bag.duplicate(),
		"player_hp": 20,
		"player_max_hp": 20,
		"pink_bonus": 0,
	}, true)
	assert_true(RunState.available_node_ids().has(3))
	var n := MapGraph.node_by_id(RunState.graph, 3)
	assert_true(MapGraph.is_shop_node(n))
	assert_true(RunState.enter_shop_node(3))
	assert_eq(RunState.pending_shop_node_id, 3)
	# 未离开前节点未完成
	assert_false(RunState.is_completed(3))
	var shop := ShopState.new()
	shop.begin(RunState.gold, RunState.bag, 3, 55)
	assert_true(shop.buy(0))
	var bought_id: int = shop.bag[shop.bag.size() - 1]
	var payload := shop.end_session()
	var msg := RunState.leave_shop(payload)
	assert_string_contains(msg, "离开商店")
	assert_eq(RunState.current_node_id, 3)
	assert_true(RunState.is_completed(3))
	assert_eq(RunState.pending_shop_node_id, -1)
	assert_eq(RunState.gold, int(payload["gold"]))
	assert_true(RunState.bag.has(bought_id))
	assert_true(RunState.available_node_ids().has(4))


func test_non_shop_placeholder_still_pass_through() -> void:
	RunState.begin_run(5, "特殊事件")
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result({
		"gold": 10,
		"bag": RunState.bag.duplicate(),
		"player_hp": 20,
		"player_max_hp": 20,
		"pink_bonus": 0,
	}, true)
	var msg := RunState.visit_placeholder(3)
	assert_string_contains(msg, "灰盒未开放")
	assert_eq(RunState.current_node_id, 3)


func test_visit_placeholder_rejects_shop() -> void:
	RunState.begin_run(5, MapGraph.KIND_SHOP)
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result({
		"gold": 10,
		"bag": RunState.bag.duplicate(),
		"player_hp": 20,
		"player_max_hp": 20,
		"pink_bonus": 0,
	}, true)
	var msg := RunState.visit_placeholder(3)
	assert_string_contains(msg, "商店")
	assert_false(RunState.is_completed(3))
