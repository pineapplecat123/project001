extends GutTest
## 超级回合子弹：射击后额外装填+自动射击；奖励池；额外轮不叠软锁。


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
	assert_true(_log_has(cs, "追加 2 轮"))
	assert_eq(cs.pending_gold_autofires(), 0)


func test_extra_round_super_round_does_not_stack() -> void:
	## 额外轮内再打出超级回合不得继续叠加（与金色一致，防软锁）。
	var cs := CombatState.new(2123)
	cs.start_graybox(2123)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	# 袋里全是超级回合：额外轮会装满超级回合，但不应再叠 pending
	for _i in 12:
		cs.bag.append(FireResolver.ID_SUPER_ROUND)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.do_fire())
	# 主匣 1 发 → pending 1 → 额外轮打完后 pending 必须清零，且日志只有一轮追加
	assert_eq(cs.pending_gold_autofires(), 0)
	var append_logs := 0
	for line in cs.last_log:
		if "追加" in str(line) and "轮" in str(line):
			append_logs += 1
	assert_eq(append_logs, 1, "only one extra-cycle batch from the main magazine")


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
