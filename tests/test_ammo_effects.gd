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
	## 整匣打完后按本匣击发金数追加额外自动装填射击一轮。
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
	# 主匣：金0 + 5白×3=15；整匣后额外轮从袋抽 6 白×3=18 → 33
	var dealt: int = hp0 - cs.enemies[0].hp
	assert_gte(dealt, 30, "gold extra round should deal additional white damage, dealt=%d" % dealt)
	assert_true(_log_has(cs, "金色弹药"), "should log gold autofire")
	assert_true(_log_has(cs, "整匣打完"), "extras should run after full magazine")
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)


func test_gold_whites_fire_before_extras_then_clear() -> void:
	## 金色整匣后触发：先打完同匣白弹；白弹清场后仍记录金色并尝试追加（场空则跳过）。
	var cs := CombatState.new(820)
	cs.start_graybox(820)
	# 平民 10HP；金0 + 白弹清场
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
	assert_eq(cs.enemies[0].hp, 20)
	assert_true(cs.begin_fire())
	var more: bool = cs.fire_next_shot()  # 仅金：0 伤，计入待追加，不立刻额外轮
	assert_true(more, "gold alone should not clear or finish")
	assert_true(_log_has(cs, "已击发金"))
	assert_false(_log_has(cs, "额外自动装填射击"), "extras must wait until magazine finishes")
	assert_eq(cs.enemies[0].hp, 20)
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
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
	cs.enemies[0].hp = 10
	cs.enemies[0].max_hp = 10
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
	# 练习战胜利=战斗结束：弃牌清空；袋回 10+5；额外罪孽清零
	assert_eq(cs.discard.size(), 0)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	assert_eq(cs.bag_reset_count, 0)
	assert_eq(cs.count_temporary_in_bag(), 0)


func test_practice_win_resets_bag_and_magazine() -> void:
	## 练习战胜利后：弹仓/弃牌清空；袋回 10+5（清额外罪孽）；再叠加奖励。
	var cs := CombatState.new(811)
	cs.start_graybox(811)
	assert_eq(cs.from_map_run, false)
	assert_eq(cs.bag_reset_count, 0)
	cs.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	cs.bag.clear()
	cs.bag_temp.clear()
	cs._bag_append(FireResolver.ID_GOLD, false)
	cs._bag_append(FireResolver.ID_FIRE, false)
	assert_true(cs.do_fire())
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_true(cs.magazine.is_empty())
	assert_eq(cs.discard.size(), 0, "practice win should clear discard")
	assert_eq(cs.bag_reset_count, 0)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	assert_eq(cs.count_temporary_in_bag(), 0)
	var white_n := 0
	var sin_n := 0
	for id in cs.bag:
		if int(id) == CombatConstants.WHITE_AMMO_ID:
			white_n += 1
		elif int(id) == cs.selected_sin_ammo_id:
			sin_n += 1
	assert_eq(white_n, CombatConstants.STARTER_WHITE_COUNT)
	assert_eq(sin_n, CombatConstants.STARTER_SIN_COUNT)
	assert_true(cs.pick_reward_ammo(0))
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL + 1)




func test_endless_win_clears_bonus_sin_like_practice() -> void:
	## 无限每波胜利=战斗结束：清 bag_reset_count / 临时额外罪孽，袋回 10+5；奖励叠加；枪口清。
	var cs := CombatState.new(840)
	cs.start_graybox(840, true, FireResolver.ID_WRATH)
	assert_eq(cs.from_map_run, false)
	assert_true(cs.endless_mode)
	assert_eq(cs.bag_reset_count, 0)
	# 先做一次袋空自动重置，使 count=1（同波内加成仍在）
	cs.bag.clear()
	cs.bag_temp.clear()
	cs._auto_reset_bag_if_empty_at_turn_start()
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.count_temporary_in_bag(), 1)
	cs.enemies[0].hp = 10
	cs.enemies[0].max_hp = 10
	cs.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	cs.bag.clear()
	cs.bag_temp.clear()
	cs._bag_append(FireResolver.ID_GOLD, false)
	cs._bag_append(FireResolver.ID_FIRE, false)
	assert_true(cs.begin_fire())
	var shots := 0
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
		shots += 1
	assert_eq(shots, 4)
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_eq(cs.discard.size(), 0)
	assert_eq(cs.bag_reset_count, 0)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	assert_eq(cs.count_temporary_in_bag(), 0)
	assert_eq(cs._muzzle_pride, 0)
	assert_eq(cs._muzzle_wrath, 0)
	assert_true(cs.pick_reward_ammo(0))
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL + 1)
	assert_true(cs.can_start_next_wave())
	assert_true(cs.start_next_wave())
	assert_eq(cs.wave_index, 2)
	assert_eq(cs.bag_reset_count, 0)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL + 1)


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
	cs.enemies.clear()
	cs.dev_spawn_enemy(CombatConstants.CIVILIAN_ENEMY_ID, 8)
	cs.enemies[0].hp = 10
	cs.enemies[0].max_hp = 10
	cs.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	# 10HP，4 白清场，剩 2 归袋
	assert_true(cs.begin_fire())
	var shots := 0
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
		shots += 1
	assert_eq(shots, 4)
	assert_eq(cs.phase, CombatState.Phase.WON)
	# 原袋 2（金）+ 归还未击发 2 = 4… 实际：袋在 force_load 前含 8 发，装走 6 后剩 2；清场归还 2 → 袋 4？
	# force_load 不从袋扣弹，袋仍 8；未击发 2 归袋 → 10；弃牌 4
	assert_eq(cs.bag.size(), 10)
	assert_eq(cs.discard.size(), 4)


func test_stone_enemy_disabled_in_combat_pool() -> void:
	## 石头人/骷髅禁用：不进刷怪池；设计数据仍在（legacy id）。
	var def: Dictionary = DataRegistry.get_enemy(105)
	assert_eq(str(def.get("name", "")), "石头人")
	assert_false(bool(def.get("enabled_in_combat", true)))
	assert_false(bool(DataRegistry.get_enemy(104).get("enabled_in_combat", true)))
	var cs := CombatState.new(821)
	cs.start_graybox(821)
	for _w in 12:
		cs.enemies.clear()
		cs.wave_index = _w + 1
		cs._spawn_wave_enemies()
		for e in cs.enemies:
			assert_ne(e.def_id, 105, "stone must not spawn when disabled")
			assert_ne(e.def_id, 104, "skeleton must not spawn when disabled")


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


func test_endless_shop_required_every_5_waves() -> void:
	## 无限：波 1–4 领奖后可直接下一波；波 5/10 须先逛店。
	var cs := CombatState.new(905)
	cs.start_graybox(905, true)
	for w in [1, 2, 3, 4]:
		_force_endless_win_at_wave(cs, w)
		assert_true(cs.pick_reward_ammo(0), "wave %d pick" % w)
		assert_false(cs.needs_endless_shop(), "wave %d no shop" % w)
		assert_true(cs.endless_shop_done)
		assert_true(cs.can_start_next_wave(), "wave %d next" % w)
	_force_endless_win_at_wave(cs, 5)
	assert_false(cs.endless_shop_done)
	assert_true(cs.reward_pending)
	assert_false(cs.can_start_next_wave())
	assert_true(cs.pick_reward_ammo(0))
	assert_true(cs.needs_endless_shop())
	assert_false(cs.can_start_next_wave())
	assert_false(cs.start_next_wave())
	var bag_before: Array = cs.bag.duplicate()
	var gold_before: int = cs.gold
	cs.apply_shop_payload({"gold": gold_before + 3, "bag": bag_before})
	assert_eq(cs.gold, gold_before + 3)
	cs.mark_endless_shop_done()
	assert_false(cs.needs_endless_shop())
	assert_true(cs.can_start_next_wave())
	assert_true(cs.start_next_wave())
	assert_eq(cs.wave_index, 6)
	# 波 10 同样须进店
	_force_endless_win_at_wave(cs, 10)
	assert_true(cs.skip_reward_for_gold())
	assert_true(cs.needs_endless_shop())
	assert_false(cs.can_start_next_wave())
	cs.mark_endless_shop_done()
	assert_true(cs.can_start_next_wave())


func _force_endless_win_at_wave(cs: CombatState, wave: int) -> void:
	cs.phase = CombatState.Phase.AWAIT_LOAD
	cs._clear_reward_state()
	cs.endless_shop_done = true
	cs.wave_index = wave
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 8)
	assert_gt(cs.alive_enemies().size(), 0)
	cs.dev_kill_all_enemies()
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_true(cs.reward_pending)


func test_endless_shop_payload_writes_bag() -> void:
	var cs := CombatState.new(906)
	cs.start_graybox(906, true)
	_force_endless_win_at_wave(cs, 5)
	assert_true(cs.skip_reward_for_gold())
	assert_true(cs.needs_endless_shop())
	var new_bag: Array = [1, 1, FireResolver.ID_GOLD]
	cs.apply_shop_payload({"gold": 42, "bag": new_bag})
	assert_eq(cs.gold, 42)
	assert_eq(cs.bag.size(), 3)
	assert_eq(cs.bag[2], FireResolver.ID_GOLD)
	cs.mark_endless_shop_done()
	assert_true(cs.start_next_wave())
	assert_eq(cs.bag.size(), 3)


func test_gold_extra_when_bag_empty_after_full_load() -> void:
	## 袋空时装满匣再开火：整匣打完后弃牌洗回，额外轮应打出实质白伤（不再「白打」）。
	var cs := CombatState.new(830)
	cs.start_graybox(830)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.discard.clear()
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_eq(cs.bag.size(), 0)
	var hp0: int = cs.enemies[0].hp
	assert_true(cs.do_fire())
	var dealt: int = hp0 - cs.enemies[0].hp
	# 主匣 5×3=15 + 额外轮洗回后至少再来几发白（金0）；总额应明显高于仅主匣
	assert_gte(dealt, 27, "empty-bag gold extras should deal substantial white dmg, dealt=%d" % dealt)
	assert_true(_log_has(cs, "金色弹药"))
	assert_true(_log_has(cs, "整匣打完") or _log_has(cs, "洗回"))


func test_gold_extras_after_remaining_whites() -> void:
	## 金在匣首：先结算同匣后续白弹伤害，额外轮在整匣结束后才出现。
	var cs := CombatState.new(831)
	cs.start_graybox(831)
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
	assert_true(cs.begin_fire())
	cs.fire_next_shot()  # gold
	assert_eq(cs.enemies[0].hp, hp0, "gold deals 0; extras not yet")
	assert_false(_log_has(cs, "额外自动装填射击"))
	# 先打 4 发白：仍未收束，额外轮未触发
	for _i in 4:
		assert_eq(cs.phase, CombatState.Phase.FIRING)
		cs.fire_next_shot()
	assert_eq(hp0 - cs.enemies[0].hp, 12, "four whites before last chamber")
	assert_false(_log_has(cs, "额外自动装填射击"))
	# 最后一发白 → 整匣收束并追加额外轮
	cs.fire_next_shot()
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
	var dealt: int = hp0 - cs.enemies[0].hp
	assert_gte(dealt, 30, "extras after whites, dealt=%d" % dealt)
	assert_true(_log_has(cs, "整匣打完"))


func test_wet_then_thunder_chains() -> void:
	## 先水后雷：两只相邻已湿敌人，雷击应从首目标导电到后排。
	var cs := CombatState.new(850)
	cs.start_graybox(850)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	for e in cs.enemies:
		e.hp = 80
		e.max_hp = 80
	cs.dev_force_load([
		FireResolver.ID_WATER,
		FireResolver.ID_WATER,
		FireResolver.ID_THUNDER,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())  # water front
	assert_true(cs.fire_next_shot())  # water — muzzle water hits front again; need both wet
	# 手动保证后排也湿（两发都打前排）；再补湿后排
	cs.enemies_sorted_by_cell()[1].wet_stacks = maxi(cs.enemies_sorted_by_cell()[1].wet_stacks, 2)
	assert_gt(cs.enemies_sorted_by_cell()[0].wet_stacks, 0)
	var back: EnemyInstance = cs.enemies_sorted_by_cell()[1]
	var hp_back0: int = back.hp
	assert_true(cs.fire_next_shot())  # thunder
	assert_lt(back.hp, hp_back0, "wet front should conduct thunder to wet back")


func test_same_shot_water_and_thunder_conducts() -> void:
	## 同发含水+雷（枪口水+雷弹）：命中后湿须已挂上才能启动导电。
	var cs := CombatState.new(841)
	cs.start_graybox(841)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	for e in cs.enemies:
		e.hp = 80
		e.max_hp = 80
		e.wet_stacks = 0
	# 后排预湿；前排靠本发水分获得湿再导电
	cs.enemies_sorted_by_cell()[1].wet_stacks = 3
	cs.dev_force_load([
		FireResolver.ID_WATER,
		FireResolver.ID_THUNDER,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())  # water mounts muzzle
	var back: EnemyInstance = cs.enemies_sorted_by_cell()[1]
	var hp0: int = back.hp
	assert_true(cs.fire_next_shot())  # thunder + muzzle water
	assert_gt(cs.enemies_sorted_by_cell()[0].wet_stacks, 0)
	assert_lt(back.hp, hp0, "same-shot water+thunder must conduct via newly applied wet")


func test_pierce_thunder_chains_from_wet() -> void:
	## 穿透+雷：首个湿目标应启动导电。
	var cs := CombatState.new(842)
	cs.start_graybox(842)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	cs.dev_spawn_enemy(1, 3)
	for e in cs.enemies:
		e.hp = 80
		e.max_hp = 80
		e.wet_stacks = 2
	cs._muzzle_pierce = true
	cs.dev_force_load([
		FireResolver.ID_THUNDER,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var sorted: Array = cs.enemies_sorted_by_cell()
	var mid_hp0: int = sorted[1].hp
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	# 穿透伤 + 导电伤，中排应比仅穿透更低；至少被传导打到
	assert_lt(sorted[1].hp, mid_hp0)


func test_endless_spawns_zombies_and_boss_super() -> void:
	## 新表：第1波平民池；第10波超级僵尸×1。
	var cs := CombatState.new(843)
	cs.start_graybox(843, true)
	assert_true(cs.endless_mode)
	assert_eq(cs.enemies.size(), 1)
	assert_eq(cs.enemies[0].def_id, 1)
	cs.phase = CombatState.Phase.WON
	cs.reward_resolved = true
	cs.reward_pending = false
	cs.endless_shop_done = true
	cs.wave_index = 9
	assert_true(cs.start_next_wave())
	assert_eq(cs.wave_index, 10)
	assert_eq(cs.encounter_kind, CombatState.EncounterKind.BOSS)
	assert_eq(cs.enemies.size(), 1)
	assert_eq(cs.enemies[0].def_id, CombatConstants.SUPER_ZOMBIE_ENEMY_ID)
	assert_eq(cs.enemies[0].max_hp, 100)


func test_super_zombie_summons_behind() -> void:
	## 表改：面前召唤（朝向玩家的更低格）。
	var cs := CombatState.new(844)
	cs.start_graybox(844, true, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(CombatConstants.SUPER_ZOMBIE_ENEMY_ID, 5)
	assert_eq(cs.enemies.size(), 1)
	cs.bag.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.do_load()
	cs.do_unload()
	var boss: EnemyInstance = null
	var zombies := 0
	var zcell := -1
	for e in cs.enemies:
		if e.def_id == CombatConstants.SUPER_ZOMBIE_ENEMY_ID:
			boss = e
		elif e.def_id == CombatConstants.ZOMBIE_ENEMY_ID:
			zombies += 1
			zcell = e.cell
	assert_eq(zombies, 1, "super zombie should summon one zombie in front")
	assert_ne(boss, null)
	assert_eq(zcell, boss.cell - 1)


func test_begin_gold_extra_load_is_stepwise_not_instant() -> void:
	## UI 金色额外：begin 后不瞬装满，需逐步 load_next_chamber；装完才可开火。
	var cs := CombatState.new(830)
	cs.start_graybox(830)
	cs.pace_after_fire = true
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.discard.clear()
	for _i in 8:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_true(cs.begin_fire())
	var guard := 0
	while cs.phase == CombatState.Phase.FIRING and guard < 20:
		cs.fire_next_shot()
		if cs.has_paced_shot_pending():
			cs.finalize_paced_shot()
		guard += 1
	assert_gt(cs.pending_gold_autofires(), 0)
	assert_true(cs.begin_gold_extra_load())
	assert_true(cs.is_busy_loading())
	assert_eq(cs.magazine.loaded_count(), 0, "must not instant-fill magazine")
	var steps := 0
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		steps += 1
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
		assert_lte(steps, CombatConstants.MAGAZINE_SIZE + 1)
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_true(cs.can_fire())
	assert_gte(steps, CombatConstants.MAGAZINE_SIZE)
