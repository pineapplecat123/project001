extends GutTest
## 超级回合子弹：射击后额外装填+自动射击；奖励池；额外轮可嵌套（有硬上限防软锁）。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _log_has(cs: CombatState, needle: String) -> bool:
	for line in cs.last_log:
		if needle in str(line):
			return true
	return false


func test_ammo_def_enabled_and_in_reward_pool() -> void:
	var def: Dictionary = DataRegistry.get_ammo(FireResolver.ID_SUPER_ROUND)
	assert_eq(str(def.get("name", "")), "超级回合子弹")
	assert_eq(int(def.get("base_damage", 0)), 1)
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(FireResolver.ID_SUPER_ROUND))
	assert_false(DataRegistry.is_ammo_ephemeral(FireResolver.ID_SUPER_ROUND))
	assert_eq(FireResolver.base_damage_for(FireResolver.ID_SUPER_ROUND, [FireResolver.ID_SUPER_ROUND], 0, 0), 1)


func test_super_round_grants_extra_load_and_autofire_after_magazine() -> void:
	## 击发超级回合后不立刻额外轮；整匣打完后追加 1 轮自动装填射击。
	var cs := CombatState.new(2121)
	cs.start_graybox(2121)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	var hp0: int = cs.enemies[0].hp
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())  # 超级回合：伤1，计入待追加
	assert_eq(cs.pending_gold_autofires(), 1)
	assert_true(_log_has(cs, "超级回合子弹"))
	assert_false(_log_has(cs, "额外自动装填射击"), "extras must wait until magazine finishes")
	assert_eq(hp0 - cs.enemies[0].hp, 1)
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
	# 主匣：1 + 5×3=16；额外轮 6 白×3=18 → 34（可能再加流血，视阶段）
	var dealt: int = hp0 - cs.enemies[0].hp
	assert_gte(dealt, 30, "extra autofire should add white damage, dealt=%d" % dealt)
	assert_true(_log_has(cs, "额外装填回合"))
	assert_true(_log_has(cs, "整匣打完"))
	assert_eq(cs.pending_gold_autofires(), 0)


func test_two_super_rounds_grant_two_extra_cycles() -> void:
	var cs := CombatState.new(2122)
	cs.start_graybox(2122)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in 12:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		FireResolver.ID_SUPER_ROUND,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY,
		Magazine.EMPTY,
		Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.do_fire())
	assert_true(_log_has(cs, "待追加 2 轮") or _log_has(cs, "追加 2 轮"))
	assert_eq(cs.pending_gold_autofires(), 0)


func test_extra_round_super_round_nests_with_cap() -> void:
	## 额外轮内再打出超级回合应继续入队；全匣超级时靠硬上限收束，pending 最终为 0。
	var cs := CombatState.new(2123)
	cs.start_graybox(2123)
	cs.enemies[0].hp = 9999
	cs.enemies[0].max_hp = 9999
	cs.bag.clear()
	cs.bag_temp.clear()
	# 袋里足够多超级回合：额外轮会再打出超级并嵌套
	for _i in 30:
		cs.bag.append(FireResolver.ID_SUPER_ROUND)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.do_fire())
	assert_eq(cs.pending_gold_autofires(), 0)
	var finished := 0
	for line in cs.last_log:
		if "额外装填回合射击完毕" in str(line):
			finished += 1
	assert_gt(finished, 1, "nested extras from id=21 in bonus round should run, got %d" % finished)
	assert_lte(finished, CombatConstants.MAX_EXTRA_AUTOFIREs_PER_CHAIN)
	# 硬上限：授予达顶时应有日志（袋极多超级时几乎必触发）
	var hit_cap := _log_has(cs, "已达上限")
	assert_true(hit_cap or finished >= 2, "cap log or at least nested extras")


func test_super_round_extra_chain_hard_cap() -> void:
	## 直接压测入队：同链授予不超过 MAX_EXTRA_AUTOFIREs_PER_CHAIN。
	var cs := CombatState.new(2126)
	cs.start_graybox(2126)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs._extra_autofires_granted_this_chain = 0
	cs._in_gold_extra_round = true  # 模拟已在额外轮
	var cap: int = CombatConstants.MAX_EXTRA_AUTOFIREs_PER_CHAIN
	for _i in cap + 5:
		cs._queue_extra_autofire_from_shot(FireResolver.ID_SUPER_ROUND)
	assert_eq(cs.pending_gold_autofires(), cap)
	assert_eq(cs._extra_autofires_granted_this_chain, cap)
	assert_true(_log_has(cs, "已达上限"))


func test_super_round_in_reward_choices_pool() -> void:
	var pool: Array[int] = []
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if DataRegistry.is_ammo_reward_eligible(aid):
			pool.append(aid)
	assert_true(FireResolver.ID_SUPER_ROUND in pool)
	assert_true(FireResolver.ID_TOMBSTONE in pool)
	assert_false(FireResolver.ID_GHOST in pool)


func test_endless_win_keeps_super_round() -> void:
	var cs := CombatState.new(2124)
	cs.start_graybox(2124, true, FireResolver.ID_WRATH)
	cs._bag_append(FireResolver.ID_SUPER_ROUND, false)
	cs._snapshot_combat_bag_baseline()
	cs.enemies[0].hp = 1
	cs.enemies[0].max_hp = 1
	cs.dev_force_load([CombatConstants.WHITE_AMMO_ID] as Array[int])
	assert_true(cs.begin_fire())
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
	assert_eq(cs.phase, CombatState.Phase.WON)
	var n := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_SUPER_ROUND:
			n += 1
	assert_eq(n, 1, "super round must survive endless wave win")


func test_tombstone_then_super_round_still_grants_extra() -> void:
	## 与墓碑爆发共存：同匣先墓碑填幽灵，再超级回合仍应计入额外轮。
	var cs := CombatState.new(2125)
	cs.start_graybox(2125)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in 8:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_TOMBSTONE,
		FireResolver.ID_SUPER_ROUND,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())  # tombstone
	assert_true(cs.fire_next_shot())  # super round amid ghosts
	assert_eq(cs.pending_gold_autofires(), 1)
	var guard := 0
	while cs.phase == CombatState.Phase.FIRING and guard < 20:
		cs.fire_next_shot()
		guard += 1
	assert_true(_log_has(cs, "额外装填回合") or _log_has(cs, "超级回合子弹"))
	assert_eq(cs.pending_gold_autofires(), 0)


func test_extra_round_sync_load_triggers_wrath_pack() -> void:
	## 同步额外轮装匣：袋内愤怒≥3 须自伤 6（此前 _auto_load 跳过惩罚）。
	var cs := CombatState.new(2127)
	cs.start_graybox(2127, false, FireResolver.ID_WRATH)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for id in [
		FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	]:
		cs.bag.append(id)
		cs.bag_temp.append(false)
	cs.magazine.clear()
	cs._in_gold_extra_round = true
	var hp0: int = cs.player_hp
	assert_true(cs._auto_load_and_fire_once())
	assert_eq(cs.player_hp, hp0 - 6, "wrath≥3 in gold/extra sync load must self-damage 6")
	assert_true(_log_has(cs, "罪孽[愤怒]"))


func test_extra_round_stepwise_load_triggers_wrath_pack() -> void:
	## UI 逐步额外装：装完匣后同样触发愤怒≥3 自伤。
	var cs := CombatState.new(2128)
	cs.start_graybox(2128, false, FireResolver.ID_WRATH)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for id in [
		FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	]:
		cs.bag.append(id)
		cs.bag_temp.append(false)
	cs._pending_gold_autofires = 1
	var hp0: int = cs.player_hp
	assert_true(cs.begin_gold_extra_load())
	var steps := 0
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		steps += 1
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
		assert_lte(steps, CombatConstants.MAGAZINE_SIZE + 1)
	assert_eq(cs.player_hp, hp0 - 6)
	assert_true(_log_has(cs, "罪孽[愤怒]"))
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)


func test_super_round_chain_extra_loads_sin_pack() -> void:
	## 实打：主匣超级回合 → 额外轮从袋装入≥3 愤怒 → 自伤生效。
	var cs := CombatState.new(2129)
	cs.start_graybox(2129, false, FireResolver.ID_WRATH)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for id in [
		FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	]:
		cs.bag.append(id)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hp0: int = cs.player_hp
	assert_true(cs.do_fire())
	assert_eq(cs.player_hp, hp0 - 6, "sin pack in super-round extra must punish")
	assert_true(_log_has(cs, "罪孽[愤怒]"))
	assert_true(_log_has(cs, "额外装填回合"))
