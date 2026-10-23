extends GutTest
## 弹药效果审计：金色额外轮、中途清场停射、练习战重置弹袋、各色关键路径。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _log_has(cs: CombatState, needle: String) -> bool:
	for line in cs.last_log:
		if needle in str(line):
			return true
	return false


func test_gold_triggers_extra_auto_load_and_fire() -> void:
	## 金弹击发后应立刻额外自动装填射击一轮。
	var cs := CombatState.new(808)
	cs.start_graybox(808)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.discard.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	var hp0: int = cs.enemies[0].hp
	assert_true(cs.do_fire())
	# 金0 + 额外轮6白×3=18 + 主匣剩5白×3=15 → 33
	var dealt: int = hp0 - cs.enemies[0].hp
	assert_gte(dealt, 30, "gold extra round should deal additional white damage, dealt=%d" % dealt)
	assert_true(_log_has(cs, "金色弹药"), "should log gold autofire")
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)


func test_gold_fires_extra_even_if_rest_of_mag_would_clear() -> void:
	## 回归：旧逻辑把金拖到整匣打完，同匣后续白弹清场后会跳过额外轮。
	var cs := CombatState.new(820)
	cs.start_graybox(820)
	# 平民 10HP；金 + 4 白足够清场，但金应先触发额外轮造成可见日志
	cs.bag.clear()
	cs.discard.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_eq(cs.enemies[0].hp, 10)
	assert_true(cs.begin_fire())
	var more: bool = cs.fire_next_shot()  # 金 → 立刻额外轮，额外轮白弹清场后停射
	assert_false(more, "should abort fire sequence after clear during gold extra")
	assert_true(_log_has(cs, "金色弹药"))
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_true(cs.alive_enemies().is_empty())


func test_gold_extra_round_keeps_muzzle() -> void:
	## 枪口效果跨金色额外轮保留（额外轮内白弹仍带火）。
	var cs := CombatState.new(809)
	cs.start_graybox(809)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.discard.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_force_load([
		FireResolver.ID_FIRE,
		FireResolver.ID_GOLD,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_true(cs.do_fire())
	assert_gt(cs.enemies[0].burn_stacks, 3, "muzzle fire should apply across gold extra round whites")


func test_fire_stops_when_enemies_cleared_mid_magazine() -> void:
	## 连射中途清场：立刻停射进胜利，不打完剩余弹；未击发归袋（练习战随后会重置袋）。
	var cs := CombatState.new(810)
	cs.start_graybox(810)
	assert_eq(cs.enemies[0].hp, 10)
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_true(cs.begin_fire())
	var shots := 0
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
		shots += 1
		assert_lte(shots, 8)
	# 10HP / 3 = 需 4 发；第4发后应 WON
	assert_eq(shots, 4, "should stop after killing shot, shots=%d" % shots)
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_true(cs.alive_enemies().is_empty())
	# 练习战胜利重置：弃牌清空，已击发不保留在 discard
	assert_eq(cs.discard.size(), 0)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_WHITE_COUNT)


func test_practice_win_resets_bag_and_magazine() -> void:
	## 练习战胜利后：弹仓/弃牌清空，袋恢复练习初始白弹（再叠加奖励选择）。
	var cs := CombatState.new(811)
	cs.start_graybox(811)
	assert_eq(cs.from_map_run, false)
	cs.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	cs.bag.clear()
	cs.bag.append(FireResolver.ID_GOLD)
	cs.bag.append(FireResolver.ID_FIRE)
	assert_true(cs.do_fire())
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_true(cs.magazine.is_empty())
	assert_eq(cs.discard.size(), 0, "practice win should clear discard")
	assert_eq(cs.bag.size(), CombatConstants.STARTER_WHITE_COUNT)
	for id in cs.bag:
		assert_eq(id, CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.pick_reward_ammo(0))
	assert_eq(cs.bag.size(), CombatConstants.STARTER_WHITE_COUNT + 1)


func test_map_run_win_does_not_reset_bag() -> void:
	## 地图 run 胜利不重置袋；中途清场未击发归袋。
	var cs := CombatState.new(812)
	cs.start_from_run({
		"gold": 5,
		"bag": [1, 1, 1, 1, 1, 1, 8, 8],
		"player_hp": 20,
		"player_max_hp": 20,
		"pink_bonus": 0,
		"encounter": "normal",
	}, 812)
	assert_true(cs.from_map_run)
	cs.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	# 平民 10HP，4 白清场，剩 2 归袋
	assert_true(cs.begin_fire())
	var shots := 0
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
		shots += 1
	assert_eq(shots, 4)
	assert_eq(cs.phase, CombatState.Phase.WON)
	# 原袋 8 + 归还未击发 2 = 10；弃牌 4
	assert_eq(cs.bag.size(), 10)
	assert_eq(cs.discard.size(), 4)


func test_stone_enemy_disabled_in_combat_pool() -> void:
	## 石头人暂时禁用：不进刷怪池；设计数据仍在。
	var def: Dictionary = DataRegistry.get_enemy(5)
	assert_eq(str(def.get("name", "")), "石头人")
	assert_false(bool(def.get("enabled_in_combat", true)))
	var cs := CombatState.new(821)
	cs.start_graybox(821)
	# 多刷几波，池中不应出现 id=5
	for _w in 12:
		cs.enemies.clear()
		cs.wave_index = _w + 1
		cs._spawn_wave_enemies()
		for e in cs.enemies:
			assert_ne(e.def_id, 5, "stone must not spawn when disabled")


func test_red_bonus_from_yellow_count() -> void:
	var order: Array[int] = [6, 4, 4]  # red + 2 yellow → red 3+3=6
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs[0], 6)
	assert_eq(dmgs[1], 2)
	assert_eq(dmgs[2], 2)


func test_blue_damage_and_six_types_double() -> void:
	var few: Array[int] = [7, 1, 1]
	var dmgs: Array[int] = FireResolver.compute_shot_damages(few, 0)
	assert_eq(dmgs[0], 3)
	var six: Array[int] = [7, 1, 2, 3, 4, 5]
	assert_true(FireResolver.blue_doubles_all(six))
	var d2: Array[int] = FireResolver.compute_shot_damages(six, 0)
	assert_eq(d2[0], (1 + 6) * 2)


func test_bw_transforms_on_load_from_prev() -> void:
	var cs := CombatState.new(813)
	cs.start_graybox(813)
	cs.enemies[0].hp = 999
	cs.last_load_ids = [1, 1, 1, 1, 4, 4] as Array[int]
	cs.dev_force_load([10, 10, 1, 1, 1, 1] as Array[int])
	var order: Array[int] = cs.magazine.fire_order()
	assert_eq(order[0], CombatConstants.WHITE_AMMO_ID)
	assert_eq(order[1], CombatConstants.WHITE_AMMO_ID)


func test_bw_no_prev_stays() -> void:
	var cs := CombatState.new(814)
	cs.start_graybox(814)
	cs.last_load_ids.clear()
	cs.dev_force_load([10, 1, 1, 1, 1, 1] as Array[int])
	assert_eq(cs.magazine.fire_order()[0], FireResolver.ID_BW)


func test_water_applies_wet_and_clears_burn() -> void:
	var cs := CombatState.new(815)
	cs.start_graybox(815)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].burn_stacks = 5
	cs.dev_force_load([
		FireResolver.ID_WATER,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	assert_eq(cs.enemies[0].burn_stacks, 0)
	assert_gt(cs.enemies[0].wet_stacks, 0)


func test_thunder_chains_across_wet() -> void:
	var cs := CombatState.new(816)
	cs.start_graybox(816)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	for e in cs.enemies:
		e.hp = 50
		e.max_hp = 50
		e.wet_stacks = 2
	cs.dev_force_load([
		FireResolver.ID_THUNDER,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var back: EnemyInstance = cs.enemies_sorted_by_cell()[1]
	var hp_back0: int = back.hp
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	assert_lt(back.hp, hp_back0, "thunder should chain to adjacent wet")


func test_gas_then_fire_ignites() -> void:
	var cs := CombatState.new(817)
	cs.start_graybox(817)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		FireResolver.ID_GAS,
		FireResolver.ID_FIRE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	assert_gt(cs.enemies[0].gas_stacks, 0)
	var hp1: int = cs.enemies[0].hp
	assert_true(cs.fire_next_shot())
	assert_eq(cs.enemies[0].gas_stacks, 0)
	assert_lt(cs.enemies[0].hp, hp1)
	assert_gt(cs.enemies[0].burn_stacks, 0)


func test_muzzle_gas_on_later_white() -> void:
	var cs := CombatState.new(818)
	cs.start_graybox(818)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		FireResolver.ID_GAS,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	var g1: int = cs.enemies[0].gas_stacks
	assert_true(cs.fire_next_shot())
	assert_gt(cs.enemies[0].gas_stacks, g1)
