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
	# 6 黄每发 5 → 30；生物被命中 6 次叠 6 层流血，怪回合结算再 -6 → 64，层数剩 5
	assert_eq(cs.enemies[0].hp, 64)
	assert_eq(cs.enemies[0].bleed_stacks, 5)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)


func test_skeleton_does_not_bleed() -> void:
	var def: Dictionary = DataRegistry.get_enemy(4)
	var e := EnemyInstance.new(def, 5)
	assert_true(e.has_tag("骷髅"))
	e.apply_hit(3)
	assert_eq(e.bleed_stacks, 0)


func test_bio_bleeds_and_ticks() -> void:
	var cs := CombatState.new(4)
	cs.start_graybox(4)
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.enemies[0].cell = 9
	# 命中叠流血
	cs.enemies[0].apply_hit(3)
	assert_eq(cs.enemies[0].bleed_stacks, 1)
	var hp_before: int = cs.enemies[0].hp
	cs.do_load()
	cs.do_unload()  # 怪回合含流血结算
	assert_eq(cs.enemies[0].hp, hp_before - 1)
	assert_eq(cs.enemies[0].bleed_stacks, 0)


func test_stone_ignores_damage_under_4() -> void:
	var def: Dictionary = DataRegistry.get_enemy(5)
	var e := EnemyInstance.new(def, 5)
	assert_eq(e.apply_hit(3), 0)
	assert_eq(e.hp, e.max_hp)
	assert_eq(e.apply_hit(4), 4)
	assert_eq(e.hp, e.max_hp - 4)


func test_stone_ignores_bleed_dot_under_4() -> void:
	var def: Dictionary = DataRegistry.get_enemy(5)
	var e := EnemyInstance.new(def, 5)
	e.bleed_stacks = 3  # 强行叠层
	var dealt := e.apply_damage(e.bleed_stacks)
	assert_eq(dealt, 0)


func test_dev_spawn_bandit() -> void:
	var cs := CombatState.new(6)
	cs.start_graybox(6)
	cs.dev_kill_all_enemies()
	cs.dev_spawn_enemy(2, 8)
	assert_eq(cs.alive_enemies().size(), 1)
	assert_eq(cs.front_enemy().name_zh, "强盗")


func test_start_next_wave_after_win() -> void:
	var cs := CombatState.new(21)
	cs.start_graybox(21)
	assert_eq(cs.wave_index, 1)
	cs.dev_kill_all_enemies()
	assert_eq(cs.phase, CombatState.Phase.WON)
	# 奖励未结算前不能下一波
	assert_true(cs.reward_pending)
	assert_false(cs.can_start_next_wave())
	assert_true(cs.pick_reward_ammo(0))
	assert_true(cs.can_start_next_wave())
	assert_true(cs.start_next_wave())
	assert_eq(cs.wave_index, 2)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	assert_gt(cs.alive_enemies().size(), 0)
	assert_false(cs.can_start_next_wave())


func test_bag_draw_is_random_not_fifo() -> void:
	## 袋无顺序：同种子多次装填，不应稳定等于「始终 pop 前端」的 FIFO 序列。
	## 用固定袋 [1,2,3,4,5,6] 不洗牌，若 FIFO 则永远先抽到 1；随机下标则多数情况首发不是 1。
	var firsts: Dictionary = {}
	for seed_v in range(100, 140):
		var cs := CombatState.new(seed_v)
		cs.start_graybox(seed_v)
		cs.bag.clear()
		for id in [1, 2, 3, 4, 5, 6]:
			cs.bag.append(id)
		cs.enemies[0].hp = 100
		cs.enemies[0].max_hp = 100
		assert_true(cs.do_load())
		var order: Array[int] = cs.magazine.fire_order()
		assert_eq(order.size(), 6)
		var key := str(order[0])
		firsts[key] = int(firsts.get(key, 0)) + 1
	assert_gt(firsts.size(), 1, "random draw should vary first chamber across seeds")


func test_apply_roll_without_enemy_turn() -> void:
	var cs := CombatState.new(33)
	cs.start_graybox(33)
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	var cell_before: int = cs.enemies[0].cell
	cs.do_load()
	var steps: int = cs.apply_roll()
	assert_gte(steps, 0)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_eq(cs.enemies[0].cell, cell_before)
	cs.resolve_after_player_action()
	assert_eq(cs.enemies[0].cell, cell_before - 1)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)


func test_reward_generate_three_choices() -> void:
	var cs := CombatState.new(7)
	cs.start_graybox(7)
	var choices := cs.generate_reward_choices()
	assert_eq(choices.size(), CombatConstants.REWARD_CHOICE_COUNT)
	for id in choices:
		assert_true(DataRegistry.is_ammo_enabled(id))


func test_reward_pick_adds_to_bag_and_base_gold() -> void:
	var cs := CombatState.new(8)
	cs.start_graybox(8)
	var bag_before := cs.bag.size()
	assert_eq(cs.gold, 0)
	cs.dev_kill_all_enemies()
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_eq(cs.gold, CombatConstants.REWARD_BASE_GOLD)
	assert_eq(cs.reward_choices.size(), 3)
	var chosen: int = cs.reward_choices[1]
	assert_true(cs.pick_reward_ammo(1))
	assert_eq(cs.bag.size(), bag_before + 1)
	assert_eq(cs.bag[cs.bag.size() - 1], chosen)
	assert_true(cs.reward_resolved)
	assert_false(cs.reward_pending)
	assert_false(cs.can_pick_reward())
	assert_true(cs.can_start_next_wave())


func test_reward_skip_for_extra_gold() -> void:
	var cs := CombatState.new(9)
	cs.start_graybox(9)
	var bag_before := cs.bag.size()
	cs.dev_kill_all_enemies()
	assert_eq(cs.gold, CombatConstants.REWARD_BASE_GOLD)
	assert_true(cs.skip_reward_for_gold())
	assert_eq(cs.gold, CombatConstants.REWARD_BASE_GOLD + CombatConstants.REWARD_SKIP_EXTRA_GOLD)
	assert_eq(cs.bag.size(), bag_before)
	assert_true(cs.reward_resolved)
	assert_true(cs.can_start_next_wave())
	# 不可重复领取
	assert_false(cs.skip_reward_for_gold())
	assert_false(cs.pick_reward_ammo(0))


func test_reward_next_wave_keeps_bag_and_gold() -> void:
	var cs := CombatState.new(11)
	cs.start_graybox(11)
	cs.dev_kill_all_enemies()
	assert_true(cs.pick_reward_ammo(0))
	var gold_after := cs.gold
	var bag_after := cs.bag.duplicate()
	assert_true(cs.start_next_wave())
	assert_eq(cs.gold, gold_after)
	assert_eq(cs.bag, bag_after)
	assert_false(cs.reward_pending)
	assert_false(cs.reward_resolved)


func test_stepwise_load_api() -> void:
	var cs := CombatState.new(42)
	cs.start_graybox(42)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	assert_true(cs.begin_load())
	assert_true(cs.is_busy_loading())
	assert_eq(cs.magazine.start_index, CombatConstants.LOAD_SESSION_INITIAL_START)
	assert_eq(cs.magazine.chamber_at_load_port(), 0)
	var n := 0
	var last: Dictionary = {}
	var loaded_slots: Array[int] = []
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		last = r
		if int(r.get("slot", -1)) >= 0:
			loaded_slots.append(int(r["slot"]))
		n += 1
		assert_lte(n, CombatConstants.MAGAZINE_SIZE + 1)
		if bool(r.get("done", false)):
			break
		# 入弹后才转盘，下一发才换上弹口仓
		cs.apply_load_rotate()
	assert_eq(n, CombatConstants.MAGAZINE_SIZE)
	assert_false(cs.is_busy_loading())
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)
	# 装满后标记需要 reroll；start_index 在 spin 前保持会话末值
	assert_true(bool(last.get("needs_spin", false)))
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_WHITE_COUNT - CombatConstants.MAGAZINE_SIZE)
	# 上弹口依次装入仓 0,1,2,3,4,5
	assert_eq(loaded_slots, [0, 1, 2, 3, 4, 5])


func test_stepwise_load_partial_when_bag_small() -> void:
	var cs := CombatState.new(5)
	cs.start_graybox(5)
	cs.bag.clear()
	for _i in 3:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.begin_load())
	var n := 0
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		n += 1
		if bool(r.get("done", false)):
			break
		cs.apply_load_rotate()
	assert_eq(n, 3)
	assert_eq(cs.magazine.loaded_count(), 3)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)


func test_ammo_detail_text_from_table() -> void:
	var text := DataRegistry.format_ammo_detail_text(1)
	assert_true(text.contains("白色子弹"))
	assert_true(text.contains("3"))
	assert_true(text.contains("常规子弹") or text.contains("无"))


func test_ammo_detail_text_invalid() -> void:
	var text := DataRegistry.format_ammo_detail_text(CombatConstants.INVALID_AMMO_ID)
	assert_true(text.contains(CombatConstants.INVALID_AMMO_NAME))
	assert_true(text.contains("0"))


func test_ammo_inventory_bag_and_mag() -> void:
	var cs := CombatState.new(42)
	cs.start_graybox(42)
	var before_bag: int = cs.bag.size()
	assert_true(cs.do_load())
	var inv: Dictionary = cs.ammo_inventory_by_id()
	assert_true(inv.has(CombatConstants.WHITE_AMMO_ID))
	var e: Dictionary = inv[CombatConstants.WHITE_AMMO_ID]
	assert_eq(int(e["mag"]), CombatConstants.MAGAZINE_SIZE)
	assert_eq(int(e["bag"]), before_bag - CombatConstants.MAGAZINE_SIZE)
	assert_eq(int(e["total"]), before_bag)


func test_load_port_and_fire_port_offsets() -> void:
	var mag := Magazine.new()
	mag.start_index = CombatConstants.LOAD_SESSION_INITIAL_START
	assert_eq(mag.chamber_at_load_port(), 0)
	assert_eq(mag.chamber_at_fire_port(), CombatConstants.LOAD_SESSION_INITIAL_START)
	mag.start_index = 0
	assert_eq(mag.chamber_at_fire_port(), 0)
	assert_eq(mag.chamber_at_load_port(), CombatConstants.LOAD_PORT_OFFSET_STEPS)


func test_stepwise_load_rotates_start_each_chamber() -> void:
	var cs := CombatState.new(7)
	cs.start_graybox(7)
	assert_true(cs.begin_load())
	var starts: Array[int] = [cs.magazine.start_index]
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		if bool(r.get("done", false)):
			break
		assert_eq(int(r.get("rotate_to", -1)), (cs.magazine.start_index + 1) % CombatConstants.MAGAZINE_SIZE)
		cs.apply_load_rotate()
		starts.append(cs.magazine.start_index)
	# 每装一发后 apply_load_rotate：1→2→3→4→5→0（最后一发不步进）
	assert_eq(starts, [1, 2, 3, 4, 5, 0])


func test_do_load_full_applies_post_spin() -> void:
	var cs := CombatState.new(99)
	cs.start_graybox(99)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	# 装满后必有 random_roll；步数∈[0,5]，start 合法
	assert_gte(cs.magazine.start_index, 0)
	assert_lt(cs.magazine.start_index, CombatConstants.MAGAZINE_SIZE)


func test_fire_consumes_top_chamber_then_advances() -> void:
	var cs := CombatState.new(3)
	cs.start_graybox(3)
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	])
	cs.magazine.set_start(2)
	assert_true(cs.begin_fire())
	var top_before: int = cs.magazine.start_index
	assert_eq(top_before, 2)
	assert_eq(cs.magazine.slots[2], CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.fire_next_shot())
	assert_eq(cs.magazine.slots[2], Magazine.EMPTY)
	assert_eq(cs.magazine.start_index, 3)


func test_reward_blurb_short() -> void:
	var blurb := DataRegistry.format_ammo_reward_blurb(1)
	assert_true(blurb.contains("伤") or blurb.contains("3") or blurb.contains("常规"))
	assert_lte(blurb.length(), 40)
	var black := DataRegistry.format_ammo_reward_blurb(2)
	assert_true(black.length() > 0)
	assert_lte(black.length(), 48)

func test_load_writes_only_load_port_each_step() -> void:
	## 每步只写入当前上弹口；未 apply_load_rotate 前重复写入同一仓。
	var cs := CombatState.new(11)
	cs.start_graybox(11)
	assert_true(cs.begin_load())
	var port0: int = cs.magazine.chamber_at_load_port()
	var r1: Dictionary = cs.load_next_chamber()
	assert_eq(int(r1["slot"]), port0)
	assert_eq(cs.magazine.loaded_count(), 1)
	# 未旋转前上弹口仍是同一仓；若再装会覆盖（API 约定每次装后应 rotate）
	assert_eq(cs.magazine.chamber_at_load_port(), port0)
	cs.apply_load_rotate()
	var port1: int = cs.magazine.chamber_at_load_port()
	assert_ne(port1, port0)
	var r2: Dictionary = cs.load_next_chamber()
	assert_eq(int(r2["slot"]), port1)
	assert_eq(cs.magazine.loaded_count(), 2)


func test_fire_consumes_fire_port_chamber() -> void:
	## 击发清空的是正上锤位仓，与 last_fired_slot / chamber_at_fire_port 一致。
	var cs := CombatState.new(13)
	cs.start_graybox(13)
	cs.dev_force_load([
		FireResolver.ID_YELLOW, FireResolver.ID_RED, FireResolver.ID_BLUE,
		FireResolver.ID_GREEN, FireResolver.ID_PURPLE, FireResolver.ID_WHITE,
	])
	cs.magazine.set_start(4)
	assert_eq(cs.magazine.chamber_at_fire_port(), 4)
	assert_eq(cs.magazine.slots[4], FireResolver.ID_PURPLE)
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	assert_eq(cs.last_fired_slot, 4)
	assert_eq(cs.magazine.slots[4], Magazine.EMPTY)
	assert_eq(cs.magazine.start_index, 5)
	assert_eq(cs.magazine.chamber_at_fire_port(), 5)


func test_wheel_port_geometry_angles() -> void:
	## 逻辑偏移与 UI 固定角约定：击发=正上(i相对0)，装弹=左上(相对+5 → -150°)。
	assert_eq(CombatConstants.FIRE_PORT_OFFSET_STEPS, 0)
	assert_eq(CombatConstants.LOAD_PORT_OFFSET_STEPS, 5)
	assert_eq(CombatConstants.LOAD_SESSION_INITIAL_START, 1)
	var mag := Magazine.new()
	for s in 6:
		mag.start_index = s
		var fire_i: int = mag.chamber_at_fire_port()
		var load_i: int = mag.chamber_at_load_port()
		assert_eq(fire_i, s)
		assert_eq(load_i, (s + 5) % 6)
		# 装弹口相对击发口固定隔 5 步（屏幕 -150° vs -90°）
		assert_eq((load_i - fire_i + 6) % 6, 5)
