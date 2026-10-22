extends GutTest
## 战斗骨架：抽弹、随机 ROLL、白弹、邻接攻击、空弹失败、逐步射击。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func test_data_registry_loads_tables() -> void:
	assert_eq(DataRegistry.get_ammo(1).get("name"), "白色子弹")
	assert_eq(DataRegistry.get_enemy(1).get("name"), "平民")
	assert_true(DataRegistry.get_tag("生物").has("effect"))
	assert_eq(int(DataRegistry.get_ammo(1).get("base_damage")), 3)
	assert_eq(int(DataRegistry.get_enemy(1).get("hp")), 10)


func test_magazine_load_and_fire_order() -> void:
	var mag := Magazine.new()
	var ids: Array[int] = [1, 1, 1, 1, 1, 1]
	assert_eq(mag.load_sequence(ids), 6)
	assert_eq(mag.fire_order(), ids)
	mag.set_start(2)
	assert_eq(mag.fire_order(), [1, 1, 1, 1, 1, 1])
	mag.load_sequence([10, 11, 12, 13, 14, 15] as Array[int])
	mag.set_start(3)
	assert_eq(mag.fire_order(), [13, 14, 15, 10, 11, 12])


func test_magazine_random_roll_keeps_relative_order() -> void:
	var mag := Magazine.new()
	mag.load_sequence([1, 2, 3, 4, 5, 6] as Array[int])
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var before: Array[int] = mag.fire_order()
	var steps: int = mag.random_roll(rng)
	var after: Array[int] = mag.fire_order()
	assert_gte(steps, 0)
	assert_eq(after.size(), before.size())
	# after 应是 before 的旋转
	var ok := false
	for rot in before.size():
		var rotated: Array[int] = []
		for i in before.size():
			rotated.append(before[(i + rot) % before.size()])
		if rotated == after:
			ok = true
			break
	assert_true(ok, "fire_order should be a rotation of prior order")


func test_magazine_random_roll_noop_when_one() -> void:
	var mag := Magazine.new()
	mag.load_sequence([9] as Array[int])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(mag.random_roll(rng), 0)
	assert_eq(mag.start_index, 0)


func test_magazine_unload() -> void:
	var mag := Magazine.new()
	mag.load_sequence([1, 1, 1] as Array[int])
	var got := mag.unload_all()
	assert_eq(got.size(), 3)
	assert_true(mag.is_empty())


func test_load_fills_magazine_from_bag() -> void:
	var cs := CombatState.new(42)
	cs.start_graybox(42)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_WHITE_COUNT)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_WHITE_COUNT - CombatConstants.MAGAZINE_SIZE)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)


func test_fire_white_damages_civilian() -> void:
	var cs := CombatState.new(7)
	cs.start_graybox(7)
	cs.do_load()
	var enemy: EnemyInstance = cs.front_enemy()
	assert_not_null(enemy)
	assert_true(cs.do_fire())
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_true(cs.alive_enemies().is_empty())


func test_stepwise_fire_api() -> void:
	var cs := CombatState.new(11)
	cs.start_graybox(11)
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.do_load()
	assert_true(cs.begin_fire())
	assert_eq(cs.phase, CombatState.Phase.FIRING)
	var shots := 0
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
		shots += 1
		assert_lte(shots, 8)
	assert_eq(shots, 6)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)


func test_roll_random_then_enemy_advances() -> void:
	var cs := CombatState.new(99)
	cs.start_graybox(99)
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	var start_cell: int = cs.enemies[0].cell
	var hp_before := cs.player_hp
	cs.do_load()
	var order_before: Array[int] = cs.magazine.fire_order()
	assert_true(cs.begin_roll())
	var order_after: Array[int] = cs.magazine.fire_order()
	# 相对循环顺序保持
	assert_eq(order_after.size(), order_before.size())
	assert_eq(cs.enemies[0].cell, start_cell - 1)
	assert_eq(cs.player_hp, hp_before)  # 远处不掉血
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)


func test_distant_enemy_multiple_turns_no_player_damage() -> void:
	var cs := CombatState.new(5)
	cs.start_graybox(5)
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.enemies[0].cell = 9
	var hp0 := cs.player_hp
	# 用 UNLOAD 把弹打入弃牌，避免只 ROLL 导致袋空且弃牌空而误判弹药耗尽
	for _i in 5:
		assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
		assert_true(cs.do_load())
		assert_true(cs.do_unload())
		assert_false(cs.is_adjacent_to_player(cs.enemies[0]))
		assert_eq(cs.player_hp, hp0)
	# 5 步后应在格 4，仍未邻接
	assert_eq(cs.enemies[0].cell, 4)
	assert_eq(cs.player_hp, hp0)


func test_only_adjacent_enemy_attacks() -> void:
	var cs := CombatState.new(1)
	cs.start_graybox(1)
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.enemies[0].cell = 2
	var hp_before := cs.player_hp
	cs.do_load()
	cs.do_unload()
	assert_eq(cs.enemies[0].cell, 1)
	assert_true(cs.is_adjacent_to_player(cs.enemies[0]))
	assert_eq(cs.player_hp, hp_before - cs.enemies[0].atk)


func test_empty_ammo_lose_does_not_zero_hp() -> void:
	var cs := CombatState.new(2)
	cs.start_graybox(2)
	cs.bag.clear()
	cs.discard.clear()
	cs.magazine.clear()
	cs.needs_reshuffle_next_load = false
	var hp_before := cs.player_hp
	assert_gt(hp_before, 0)
	assert_true(cs.do_load())
	assert_eq(cs.phase, CombatState.Phase.LOST)
	assert_eq(cs.lose_reason, CombatState.LoseReason.AMMO_EXHAUSTED)
	assert_eq(cs.player_hp, hp_before)


func test_unload_discards_and_enemy_turn() -> void:
	var cs := CombatState.new(3)
	cs.start_graybox(3)
	cs.enemies[0].hp = 100
	cs.do_load()
	var loaded := cs.magazine.loaded_count()
	assert_true(cs.do_unload())
	assert_true(cs.magazine.is_empty())
	assert_eq(cs.discard.size(), loaded)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)


func test_white_bullet_damage_value() -> void:
	assert_eq(BulletEffectRegistry.compute_damage(CombatConstants.WHITE_AMMO_ID), 3)


func test_yellow_damage_by_count() -> void:
	var order: Array[int] = [4, 4, 4]
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs, [3, 3, 3])


func test_black_strict_majority_triples() -> void:
	var order: Array[int] = [2, 2, 2, 1]
	assert_true(FireResolver.black_triggers(order))
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs[3], 9)  # white 3*3
	# 并列最多不触发
	var tied: Array[int] = [2, 2, 1, 1]
	assert_false(FireResolver.black_triggers(tied))


func test_purple_run_damage() -> void:
	var order: Array[int] = [5, 5, 1]
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs[0], 3)
	assert_eq(dmgs[1], 3)
	assert_eq(dmgs[2], 3)


func test_green_trailing_multiplier() -> void:
	var order: Array[int] = [1, 3, 3]
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	# last green 2*2=4, second-last green 2*3=6
	assert_eq(dmgs[2], 4)
	assert_eq(dmgs[1], 6)
	var allg: Array[int] = [3, 3, 3]
	var z: Array[int] = FireResolver.compute_shot_damages(allg, 0)
	assert_eq(z, [0, 0, 0])


func test_pink_bonus_on_unload() -> void:
	var cs := CombatState.new(8)
	cs.start_graybox(8)
	cs.enemies[0].hp = 100
	cs.dev_force_load([9, 9, 1, 1, 1, 1] as Array[int])
	assert_eq(cs.pink_bonus, 0)
	assert_true(cs.do_unload())
	assert_eq(cs.pink_bonus, 1)


func test_force_load_yellow_and_fire() -> void:
	var cs := CombatState.new(8)
	cs.start_graybox(8)
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.dev_force_load([4, 4, 4, 4, 4, 4] as Array[int])
	assert_true(cs.do_fire())
	# 6 黄每发 5 → 30
	assert_eq(cs.enemies[0].hp, 70)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
