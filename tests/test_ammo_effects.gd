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




func test_endless_win_keeps_bag() -> void:
	## 无限模式胜利：不重置牌库；中途清场未击发归袋；奖励弹叠加入袋；可下一波。
	var cs := CombatState.new(840)
	cs.start_graybox(840, true)
	assert_eq(cs.from_map_run, false)
	assert_true(cs.endless_mode)
	cs.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	cs.bag.clear()
	cs.bag.append(FireResolver.ID_GOLD)
	cs.bag.append(FireResolver.ID_FIRE)
	assert_true(cs.begin_fire())
	var shots := 0
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
		shots += 1
	# 平民 10HP / 白弹 3 → 约 4 发清场，剩 2 归袋
	assert_eq(shots, 4)
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_eq(cs.discard.size(), 4)
	# 原袋 2 + 归还未击发 2 = 4（不重置成 12 白）
	assert_eq(cs.bag.size(), 4)
	assert_true(cs.bag.has(FireResolver.ID_GOLD))
	assert_true(cs.bag.has(FireResolver.ID_FIRE))
	assert_true(cs.pick_reward_ammo(0))
	assert_eq(cs.bag.size(), 5)
	assert_true(cs.can_start_next_wave())
	assert_true(cs.start_next_wave())
	assert_eq(cs.wave_index, 2)
	assert_eq(cs.bag.size(), 5)


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


func test_pink_unload_bonus_shared_on_later_pinks() -> void:
	## 一次卸除含多粉只 +1；加成作用于之后所有粉伤害。
	var cs := CombatState.new(830)
	cs.start_graybox(830)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([9, 9, 9, 1, 1, 1] as Array[int])
	assert_true(cs.do_unload())
	assert_eq(cs.pink_bonus, 1, "multi-pink unload counts once")
	# 清空弃牌便于观察；再装粉射击
	cs.discard.clear()
	cs.dev_skip_enemy_turn()
	cs.dev_force_load([9, 9, 1, 1, 1, 1] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())  # pink → 3+1=4
	assert_eq(hp0 - cs.enemies[0].hp, 4)
	hp0 = cs.enemies[0].hp
	assert_true(cs.fire_next_shot())  # second pink also 4
	assert_eq(hp0 - cs.enemies[0].hp, 4)


func test_yellow_ladder_and_red_with_zero_yellow() -> void:
	assert_eq(FireResolver.compute_shot_damages([4] as Array[int], 0), [1])
	assert_eq(FireResolver.compute_shot_damages([4, 4] as Array[int], 0), [2, 2])
	assert_eq(FireResolver.compute_shot_damages([4, 4, 4, 4, 4] as Array[int], 0), [5, 5, 5, 5, 5])
	assert_eq(FireResolver.compute_shot_damages([4, 4, 4, 4, 4, 4] as Array[int], 0), [5, 5, 5, 5, 5, 5])
	# 红无黄：基础 3
	assert_eq(FireResolver.compute_shot_damages([6, 1, 1] as Array[int], 0)[0], 3)
	# 红+5黄：3+7=10
	var r5: Array[int] = [6, 4, 4, 4, 4, 4]
	assert_eq(FireResolver.compute_shot_damages(r5, 0)[0], 10)


func test_purple_single_zero_and_long_run() -> void:
	assert_eq(FireResolver.compute_shot_damages([5, 1] as Array[int], 0)[0], 0)
	var run4: Array[int] = [5, 5, 5, 5]
	var d: Array[int] = FireResolver.compute_shot_damages(run4, 0)
	assert_eq(d, [5, 5, 5, 5])


func test_green_interrupted_only_trailing_counts() -> void:
	## 中间被打断：只计末尾连绿；打断前的绿按基础×1。
	var order: Array[int] = [3, 1, 3, 3]
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs[0], 2)  # 非末尾段
	assert_eq(dmgs[1], 3)
	assert_eq(dmgs[2], 6)  # 倒数第二绿 2*3
	assert_eq(dmgs[3], 4)  # 末绿 2*2


func test_black_triples_whole_mag_when_strict_majority() -> void:
	var order: Array[int] = [2, 2, 2, 6, 1]  # 3黑 > 其它
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs[0], 0)
	assert_eq(dmgs[3], 9)  # red 3*3
	assert_eq(dmgs[4], 9)  # white 3*3


func test_muzzle_water_on_later_white() -> void:
	var cs := CombatState.new(831)
	cs.start_graybox(831)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].burn_stacks = 4
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
	assert_true(cs.fire_next_shot())  # water
	assert_eq(cs.enemies[0].burn_stacks, 0)
	var wet1: int = cs.enemies[0].wet_stacks
	assert_gt(wet1, 0)
	cs.enemies[0].burn_stacks = 3  # 人为再烧，验证后续白仍带水清燃
	assert_true(cs.fire_next_shot())
	assert_eq(cs.enemies[0].burn_stacks, 0)
	assert_gte(cs.enemies[0].wet_stacks, wet1)


func test_muzzle_thunder_on_later_white() -> void:
	var cs := CombatState.new(832)
	cs.start_graybox(832)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	for e in cs.enemies:
		e.hp = 80
		e.max_hp = 80
		e.wet_stacks = 3
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
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())  # thunder chains
	var hp1: int = back.hp
	assert_true(cs.fire_next_shot())  # white + muzzle thunder should chain again
	assert_lt(back.hp, hp1, "muzzle thunder should chain on later white")


func test_gas_cluster_ignites_adjacent_on_fire() -> void:
	## 两只相邻怪都有汽油，火命中前排应连片引爆后排。
	var cs := CombatState.new(833)
	cs.start_graybox(833)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	var front: EnemyInstance = cs.enemies_sorted_by_cell()[0]
	var back: EnemyInstance = cs.enemies_sorted_by_cell()[1]
	front.hp = 100
	front.max_hp = 100
	back.hp = 100
	back.max_hp = 100
	front.gas_stacks = 5
	back.gas_stacks = 4
	cs.dev_force_load([
		FireResolver.ID_FIRE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp_back0: int = back.hp
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	assert_eq(front.gas_stacks, 0)
	assert_eq(back.gas_stacks, 0, "adjacent gas should ignite with cluster")
	assert_lt(back.hp, hp_back0)
	assert_gt(back.burn_stacks, 0)


func test_pierce_damage_falloff_across_enemies() -> void:
	var cs := CombatState.new(834)
	cs.start_graybox(834)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	cs.dev_spawn_enemy(1, 3)
	for e in cs.enemies:
		e.hp = 50
		e.max_hp = 50
	cs.dev_force_load([
		FireResolver.ID_PIERCE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var sorted: Array = cs.enemies_sorted_by_cell()
	var hp0: Array[int] = [sorted[0].hp, sorted[1].hp, sorted[2].hp]
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	# pierce base 3 → 3/2/1
	assert_eq(hp0[0] - sorted[0].hp, 3)
	assert_eq(hp0[1] - sorted[1].hp, 2)
	assert_eq(hp0[2] - sorted[2].hp, 1)


func test_bw_transforms_to_tied_most_common() -> void:
	## 并列最多时变形为候选之一（白或黄）。
	var cs := CombatState.new(835)
	cs.start_graybox(835)
	cs.last_load_ids = [1, 1, 4, 4, 2, 3] as Array[int]
	cs.dev_force_load([10, 1, 1, 1, 1, 1] as Array[int])
	var got: int = cs.magazine.fire_order()[0]
	assert_true(got == CombatConstants.WHITE_AMMO_ID or got == FireResolver.ID_YELLOW)
