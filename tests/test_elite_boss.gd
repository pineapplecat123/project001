extends GutTest
## 精英战数值倍率 + Boss 终战塞无效弹（灰盒暂定）。

const MapGraph = preload("res://scripts/map/map_graph.gd")


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	RunState.end_run()


func test_mini_graph_has_one_elite() -> void:
	var g := MapGraph.build_mini(42)
	var elite_n := 0
	for n in g["nodes"]:
		if int(n["type"]) == MapGraph.NodeType.ELITE:
			elite_n += 1
			assert_eq(str(n.get("label", "")), "精英")
	assert_eq(elite_n, 1)
	assert_eq(int(MapGraph.node_by_id(g, 4).get("type", -1)), MapGraph.NodeType.ELITE)
	assert_eq(int(MapGraph.node_by_id(g, 5).get("type", -1)), MapGraph.NodeType.FINALE)


func test_elite_encounter_scales_hp_atk_and_reward_gold() -> void:
	RunState.begin_run(101)
	assert_true(RunState.enter_combat_node(1))
	# 先打完支线战斗，走到精英节点 4 需经过占位 3
	RunState.apply_combat_result({
		"gold": 10,
		"bag": RunState.bag.duplicate(),
		"player_hp": 20,
		"player_max_hp": 20,
		"pink_bonus": 0,
	}, true)
	# 强制占位为特殊事件以便路过
	var n3: Dictionary = MapGraph.node_by_id(RunState.graph, 3)
	# 无论商店/休息/事件，都能前进到 4：若是商店/休息用 visit 会拒，改直接伪造进度
	if MapGraph.is_shop_node(n3) or MapGraph.is_rest_node(n3):
		RunState.completed_ids.append(3)
		RunState.current_node_id = 3
	else:
		RunState.visit_placeholder(3)
	assert_true(RunState.available_node_ids().has(4))
	assert_eq(RunState.encounter_for_node(4), "elite")
	assert_true(RunState.enter_combat_node(4))
	var snap := RunState.combat_snapshot()
	assert_eq(str(snap.get("encounter", "")), "elite")
	var cs := CombatState.new(101)
	cs.start_from_run(snap, 101)
	assert_eq(cs.encounter_kind, CombatState.EncounterKind.ELITE)
	assert_eq(cs.alive_enemies().size(), CombatConstants.ELITE_ENEMY_COUNT)
	for e in cs.alive_enemies():
		var base: Dictionary = DataRegistry.get_enemy(e.def_id)
		var expect_hp: int = maxi(1, int(round(float(base["hp"]) * CombatConstants.ELITE_HP_MULT)))
		var expect_atk: int = maxi(0, int(round(float(base["atk"]) * CombatConstants.ELITE_ATK_MULT)))
		assert_eq(e.max_hp, expect_hp)
		assert_eq(e.atk, expect_atk)
		assert_eq(e.attack_range, CombatConstants.ELITE_ATTACK_RANGE)
		assert_string_contains(e.name_zh, "精英·")
	assert_eq(cs.reward_base_gold_for_encounter(), CombatConstants.REWARD_ELITE_BASE_GOLD)
	# 清场领奖金
	cs.dev_kill_all_enemies()
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_eq(cs.last_reward_base_gold, CombatConstants.REWARD_ELITE_BASE_GOLD)
	assert_eq(cs.gold, 10 + CombatConstants.REWARD_ELITE_BASE_GOLD)


func test_boss_injects_invalid_ammo_and_zero_damage() -> void:
	var cs := CombatState.new(202)
	cs.start_from_run({
		"gold": 5,
		"bag": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
		"player_hp": 20,
		"player_max_hp": 20,
		"pink_bonus": 0,
		"seed": 202,
		"encounter": "boss",
	}, 202)
	assert_eq(cs.encounter_kind, CombatState.EncounterKind.BOSS)
	assert_eq(cs.alive_enemies().size(), 1)
	var boss: EnemyInstance = cs.front_enemy()
	assert_not_null(boss)
	assert_eq(boss.def_id, CombatConstants.BOSS_BODY_ENEMY_ID)
	var base: Dictionary = DataRegistry.get_enemy(CombatConstants.BOSS_BODY_ENEMY_ID)
	assert_eq(boss.max_hp, maxi(1, int(round(float(base["hp"]) * CombatConstants.BOSS_HP_MULT))))
	assert_eq(boss.atk, maxi(0, int(round(float(base["atk"]) * CombatConstants.BOSS_ATK_MULT))))
	assert_string_contains(boss.name_zh, "Boss·")
	# 开场塞无效弹
	var invalid_n := 0
	for id in cs.bag:
		if id == CombatConstants.INVALID_AMMO_ID:
			invalid_n += 1
	assert_eq(invalid_n, CombatConstants.BOSS_INVALID_ON_START)
	assert_eq(cs._ammo_name(CombatConstants.INVALID_AMMO_ID), CombatConstants.INVALID_AMMO_NAME)
	# 无效弹伤害为 0
	assert_eq(FireResolver.base_damage_for(CombatConstants.INVALID_AMMO_ID, [CombatConstants.INVALID_AMMO_ID], 0, 0), 0)
	var dmg := FireResolver.compute_shot_damages([CombatConstants.INVALID_AMMO_ID, 1], 0)
	assert_eq(dmg[0], 0)
	assert_eq(dmg[1], 3)
	# 怪物回合再塞（卸除进弃牌，不回袋；Boss 向袋塞无效弹）
	var bag_before := cs.bag.size()
	boss.hp = 999
	boss.max_hp = 999
	cs.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	assert_true(cs.do_unload())  # 进怪物回合
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	var after_invalid := 0
	for id in cs.bag:
		if id == CombatConstants.INVALID_AMMO_ID:
			after_invalid += 1
	assert_eq(after_invalid, CombatConstants.BOSS_INVALID_ON_START + CombatConstants.BOSS_INVALID_PER_ENEMY_TURN)
	assert_eq(cs.bag.size(), bag_before + CombatConstants.BOSS_INVALID_PER_ENEMY_TURN)


func test_boss_reward_gold_and_finale_finishes_run() -> void:
	RunState.begin_run(303, "特殊事件")
	assert_true(RunState.enter_combat_node(1))
	RunState.apply_combat_result(_snap(10), true)
	RunState.visit_placeholder(3)
	assert_true(RunState.enter_combat_node(4))  # elite
	assert_eq(RunState.encounter_for_node(4), "elite")
	RunState.apply_combat_result(_snap(20), true)
	assert_true(RunState.enter_combat_node(5))
	assert_eq(RunState.encounter_for_node(5), "boss")
	var cs := CombatState.new(303)
	cs.start_from_run(RunState.combat_snapshot(), 303)
	assert_eq(cs.encounter_kind, CombatState.EncounterKind.BOSS)
	cs.dev_kill_all_enemies()
	assert_eq(cs.last_reward_base_gold, CombatConstants.REWARD_BOSS_BASE_GOLD)
	assert_true(cs.pick_reward_ammo(0))
	var payload := cs.export_run_payload()
	RunState.apply_combat_result(payload, true)
	assert_true(RunState.run_finished)
	assert_string_contains(RunState.last_message, "通关")
	assert_string_contains(RunState.last_message, "Boss")


func test_can_attack_player_uses_attack_range() -> void:
	var cs := CombatState.new(1)
	cs.start_graybox(1)
	var e: EnemyInstance = cs.front_enemy()
	e.cell = 2
	e.attack_range = 1
	assert_false(cs.can_attack_player(e))
	e.attack_range = 2
	assert_true(cs.can_attack_player(e))
	e.cell = 1
	e.attack_range = 1
	assert_true(cs.can_attack_player(e))


func _snap(gold: int, hp: int = -1) -> Dictionary:
	return {
		"gold": gold,
		"bag": RunState.bag.duplicate(),
		"player_hp": RunState.player_hp if hp < 0 else hp,
		"player_max_hp": RunState.player_max_hp,
		"pink_bonus": RunState.pink_bonus,
	}
