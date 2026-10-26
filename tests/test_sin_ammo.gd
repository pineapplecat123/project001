extends GutTest
## 罪孽：开局 10+5、装≥3 负面、枪口叠层、敌人数值与超僵面前召唤。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func test_starter_bag_is_ten_mediocre_plus_five_sin() -> void:
	var cs := CombatState.new(901)
	cs.start_graybox(901, false, FireResolver.ID_GREED)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	var white := 0
	var sin_n := 0
	for id in cs.bag:
		if int(id) == CombatConstants.WHITE_AMMO_ID:
			white += 1
		elif int(id) == FireResolver.ID_GREED:
			sin_n += 1
	assert_eq(white, 10, "must be 10 mediocre/white")
	assert_eq(sin_n, 5, "must be 5 chosen sin")
	assert_eq(cs.selected_sin_ammo_id, FireResolver.ID_GREED)


func test_choose_sin_refills_bag() -> void:
	var cs := CombatState.new(902)
	cs.start_graybox(902, false, FireResolver.ID_WRATH)
	cs.choose_sin(FireResolver.ID_PRIDE)
	assert_eq(cs.selected_sin_ammo_id, FireResolver.ID_PRIDE)
	var pride := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_PRIDE:
			pride += 1
	assert_eq(pride, 5)
	assert_eq(cs.bag.size(), 15)


func test_wrath_pack_of_three_self_damage() -> void:
	var cs := CombatState.new(903)
	cs.start_graybox(903, false, FireResolver.ID_WRATH)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	for id in [FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]:
		cs.bag.append(id)
	var hp0: int = cs.player_hp
	assert_true(cs.do_load())
	assert_eq(cs.player_hp, hp0 - 6)


func test_wrath_muzzle_doubles_damage() -> void:
	var cs := CombatState.new(904)
	cs.start_graybox(904, false, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 500
	cs.enemies[0].max_hp = 500
	cs.dev_force_load([
		FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	assert_true(cs.begin_fire())
	var hp0: int = cs.enemies[0].hp
	assert_true(cs.fire_next_shot())
	assert_eq(cs._muzzle_wrath, 1)
	assert_eq(hp0 - cs.enemies[0].hp, 6)


func test_pride_pack_pulls_enemies_forward() -> void:
	var cs := CombatState.new(905)
	cs.start_graybox(905, false, FireResolver.ID_PRIDE)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 7)
	cs.dev_spawn_enemy(1, 9)
	cs.bag.clear()
	for id in [FireResolver.ID_PRIDE, FireResolver.ID_PRIDE, FireResolver.ID_PRIDE,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]:
		cs.bag.append(id)
	assert_true(cs.do_load())
	var cells: Array = []
	for e in cs.enemies_sorted_by_cell():
		cells.append(e.cell)
	assert_eq(cells, [1, 2])


func test_greed_pack_subtracts_gold() -> void:
	var cs := CombatState.new(906)
	cs.start_graybox(906, false, FireResolver.ID_GREED)
	cs.gold = 2
	cs.bag.clear()
	for id in [FireResolver.ID_GREED, FireResolver.ID_GREED, FireResolver.ID_GREED,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]:
		cs.bag.append(id)
	assert_true(cs.do_load())
	assert_eq(cs.gold, -4)


func test_pride_persists_greed_clears_end_of_turn() -> void:
	var cs := CombatState.new(907)
	cs.start_graybox(907, false, FireResolver.ID_PRIDE)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].cell = 9
	cs._muzzle_pride = 2
	cs._muzzle_greed = 3
	cs._muzzle_wrath = 1
	cs.do_load()
	cs.do_unload()
	assert_eq(cs._muzzle_pride, 2)
	assert_eq(cs._muzzle_greed, 0)
	assert_eq(cs._muzzle_wrath, 0)


func test_enemy_table_hp_and_zombie_tag() -> void:
	assert_eq(int(DataRegistry.get_enemy(1).get("hp")), 20)
	assert_eq(int(DataRegistry.get_enemy(2).get("hp")), 30)
	assert_eq(int(DataRegistry.get_enemy(3).get("hp")), 40)
	assert_eq(int(DataRegistry.get_enemy(6).get("hp")), 50)
	var tags = DataRegistry.get_enemy(6).get("tags", [])
	assert_true("僵尸" in tags)
	assert_eq(int(DataRegistry.get_enemy(7).get("hp")), 100)


func test_super_zombie_summons_in_front() -> void:
	var cs := CombatState.new(908)
	cs.start_graybox(908, true, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(CombatConstants.SUPER_ZOMBIE_ENEMY_ID, 5)
	cs.do_load()
	cs.do_unload()
	var boss: EnemyInstance = null
	var zcell := -1
	for e in cs.enemies:
		if e.def_id == CombatConstants.SUPER_ZOMBIE_ENEMY_ID:
			boss = e
		elif e.def_id == CombatConstants.ZOMBIE_ENEMY_ID:
			zcell = e.cell
	assert_ne(boss, null)
	assert_eq(zcell, boss.cell - 1, "summon must be in front (toward player)")


func test_zombie_regens_five_hp() -> void:
	var cs := CombatState.new(909)
	cs.start_graybox(909, true, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(CombatConstants.ZOMBIE_ENEMY_ID, 8)
	cs.enemies[0].hp = 20
	cs.enemies[0].max_hp = 50
	cs.do_load()
	cs.do_unload()
	assert_eq(cs.enemies[0].hp, 25)


func test_manual_load_one_chamber_at_a_time() -> void:
	var cs := CombatState.new(910)
	cs.start_graybox(910, false, FireResolver.ID_WRATH)
	cs.bag.clear()
	for _i in 3:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.can_manual_load())
	assert_true(cs.begin_load())
	var r1: Dictionary = cs.load_next_chamber()
	assert_true(bool(r1.get("ok", false)))
	assert_false(bool(r1.get("done", false)))
	assert_eq(cs.magazine.loaded_count(), 1)
	assert_true(cs.can_manual_load())
	cs.apply_load_rotate()
	var r2: Dictionary = cs.load_next_chamber()
	assert_true(bool(r2.get("ok", false)))
	assert_eq(cs.magazine.loaded_count(), 2)
	cs.apply_load_rotate()
	var r3: Dictionary = cs.load_next_chamber()
	assert_true(bool(r3.get("ok", false)))
	assert_true(bool(r3.get("done", false)), "bag empty after 3rd should complete session")
	assert_eq(cs.magazine.loaded_count(), 3)
	assert_false(cs.is_busy_loading())
	assert_false(cs.can_manual_load())


func test_manual_load_one_then_can_continue_and_fire() -> void:
	## 手装 1 发后仍可再装；且可直接开火（提交装填会话）。
	var cs := CombatState.new(920)
	cs.start_graybox(920, false, FireResolver.ID_WRATH)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	for _i in 4:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.begin_load())
	var r1: Dictionary = cs.load_next_chamber()
	assert_true(bool(r1.get("ok", false)))
	assert_false(bool(r1.get("done", false)))
	assert_eq(cs.magazine.loaded_count(), 1)
	assert_true(cs.is_busy_loading())
	assert_true(cs.can_manual_load(), "should still manual-load after 1")
	assert_true(cs.can_fire(), "should be able to fire after 1 manual load")
	cs.apply_load_rotate()
	var r2: Dictionary = cs.load_next_chamber()
	assert_true(bool(r2.get("ok", false)))
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_true(cs.can_fire())
	assert_true(cs.begin_fire())
	assert_false(cs.is_busy_loading(), "fire should commit load session")
	assert_eq(cs.phase, CombatState.Phase.FIRING)


func test_bag_reset_bonus_sin_accumulates_then_clears_on_new_combat() -> void:
	## 战斗内重置两次 → 额外罪孽 +1、+2；新开战斗清零无额外。
	var cs := CombatState.new(921)
	cs.start_graybox(921, false, FireResolver.ID_GREED)
	assert_eq(cs.bag_reset_count, 0)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	cs.dev_kill_all_enemies()
	assert_eq(cs.bag_reset_count, 1)
	var sin1 := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GREED:
			sin1 += 1
	assert_eq(sin1, CombatConstants.STARTER_SIN_COUNT + 1)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL + 1)
	assert_eq(cs._muzzle_pride, 0)
	assert_true(cs.skip_reward_for_gold())
	assert_true(cs.start_next_wave())
	cs.dev_kill_all_enemies()
	assert_eq(cs.bag_reset_count, 2)
	var sin2 := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GREED:
			sin2 += 1
	assert_eq(sin2, CombatConstants.STARTER_SIN_COUNT + 2)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL + 2)
	# 新开一场：计数清零，袋回 10+5
	cs.start_graybox(922, false, FireResolver.ID_GREED)
	assert_eq(cs.bag_reset_count, 0)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	var sin0 := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GREED:
			sin0 += 1
	assert_eq(sin0, CombatConstants.STARTER_SIN_COUNT)


func test_win_clears_all_sin_muzzle_including_pride() -> void:
	var cs := CombatState.new(923)
	cs.start_graybox(923, false, FireResolver.ID_PRIDE)
	cs._muzzle_pride = 3
	cs._muzzle_wrath = 2
	cs._muzzle_greed = 1
	cs._muzzle_fire = true
	cs.dev_kill_all_enemies()
	assert_eq(cs._muzzle_pride, 0)
	assert_eq(cs._muzzle_wrath, 0)
	assert_eq(cs._muzzle_greed, 0)
	assert_eq(cs._muzzle_fire, false)


func test_pride_pack_four_or_more_also_pulls() -> void:
	## 口头：≥3 触发；4 发傲慢也应拉近。
	var cs := CombatState.new(930)
	cs.start_graybox(930, false, FireResolver.ID_PRIDE)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 7)
	cs.dev_spawn_enemy(1, 9)
	cs.bag.clear()
	for id in [FireResolver.ID_PRIDE, FireResolver.ID_PRIDE, FireResolver.ID_PRIDE, FireResolver.ID_PRIDE,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]:
		cs.bag.append(id)
	assert_true(cs.do_load())
	var cells: Array = []
	for e in cs.enemies_sorted_by_cell():
		cells.append(e.cell)
	assert_eq(cells, [1, 2])


func test_manual_load_three_pride_then_fire_pulls() -> void:
	## 手装 3 傲慢后提交会话（开火），也应拉近。袋内仅傲慢，避免随机抽偏。
	var cs := CombatState.new(931)
	cs.start_graybox(931, false, FireResolver.ID_PRIDE)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 8)
	cs.bag.clear()
	for _i in 5:
		cs.bag.append(FireResolver.ID_PRIDE)
	assert_true(cs.begin_load())
	for _i in 3:
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
	assert_true(cs.is_busy_loading(), "3/6 手装后会话应仍进行")
	assert_eq(cs.enemies[0].cell, 8, "提交前尚未拉近")
	assert_true(cs.begin_fire(), "开火应提交装填会话")
	assert_eq(cs.enemies[0].cell, 1)


func test_outgoing_damage_rounds_half_up() -> void:
	## 傲慢×1 → ×1.25；底伤 3 → 3.75 → 四舍五入 4（旧 floor 会得 3）。
	var cs := CombatState.new(932)
	cs.start_graybox(932, false, FireResolver.ID_PRIDE)
	cs._muzzle_pride = 1
	assert_eq(cs._scale_outgoing_damage(3), 4)
	assert_eq(cs.muzzle_outgoing_multiplier(), 1.25)
	cs._muzzle_wrath = 1
	# ×2 × 1.25 = 2.5；3×2.5=7.5 → 8
	assert_eq(cs._scale_outgoing_damage(3), 8)


func test_muzzle_damage_tip_no_mod_and_with_stacks() -> void:
	var cs := CombatState.new(933)
	cs.start_graybox(933, false, FireResolver.ID_WRATH)
	var tip0 := cs.muzzle_damage_tip_text()
	assert_true(tip0.contains("无修正") or tip0.contains("×1"))
	cs._muzzle_wrath = 2
	cs._muzzle_pride = 1
	var tip := cs.muzzle_damage_tip_text()
	assert_true(tip.contains("愤怒"))
	assert_true(tip.contains("傲慢"))
	assert_true(tip.contains("合成输出倍率"))
	assert_true(tip.contains("四舍五入"))


func test_lose_clears_pride_muzzle() -> void:
	var cs := CombatState.new(934)
	cs.start_graybox(934, false, FireResolver.ID_PRIDE)
	cs._muzzle_pride = 4
	cs._muzzle_wrath = 2
	cs.player_hp = 0
	cs._lose_hp()
	assert_eq(cs.phase, CombatState.Phase.LOST)
	assert_eq(cs._muzzle_pride, 0)
	assert_eq(cs._muzzle_wrath, 0)


func test_next_wave_clears_pride() -> void:
	var cs := CombatState.new(935)
	cs.start_graybox(935, true, FireResolver.ID_PRIDE)
	cs._muzzle_pride = 3
	cs.dev_kill_all_enemies()
	assert_eq(cs._muzzle_pride, 0)
	assert_true(cs.skip_reward_for_gold())
	assert_true(cs.start_next_wave())
	assert_eq(cs._muzzle_pride, 0)


func test_greed_gold_gained_signal_emits_amount() -> void:
	var cs := CombatState.new(936)
	cs.start_graybox(936, false, FireResolver.ID_GREED)
	cs._muzzle_greed = 10
	cs.rng.seed = 1
	var got: Array = []
	cs.gold_gained.connect(func(cell, amount): got.append([cell, amount]))
	# 强制多次掉金：层数高 + 固定种子
	cs._try_greed_gold_drop(6, 3)
	assert_gt(got.size(), 0, "should emit at least one gold float")
	assert_eq(got[0][0], 3)
	assert_eq(got[0][1], 6)

