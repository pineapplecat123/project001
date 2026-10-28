extends GutTest
## 穿甲弹药（设计表#12 → 运行时 id=22）：挂枪口【穿甲】；递减穿怪；奖励池；袋/仓钢青辉光。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _log_has(cs: CombatState, needle: String) -> bool:
	for line in cs.last_log:
		if needle in str(line):
			return true
	return false


func test_ammo_def_enabled_and_in_reward_pool() -> void:
	var def: Dictionary = DataRegistry.get_ammo(FireResolver.ID_ARMOR_PIERCE)
	assert_eq(str(def.get("name", "")), "穿甲弹药")
	assert_eq(int(def.get("base_damage", 0)), 3)
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(FireResolver.ID_ARMOR_PIERCE))
	assert_false(DataRegistry.is_ammo_ephemeral(FireResolver.ID_ARMOR_PIERCE))
	assert_eq(FireResolver.base_damage_for(FireResolver.ID_ARMOR_PIERCE, [FireResolver.ID_ARMOR_PIERCE], 0, 0), 3)
	var flags := FireResolver.inherits_from(FireResolver.ID_ARMOR_PIERCE)
	assert_true(bool(flags.get("pierce", false)))


func test_armor_pierce_damage_falloff_across_enemies() -> void:
	## 本发穿甲：首个全伤，之后每穿一个 -1，至 0。
	var cs := CombatState.new(2210)
	cs.start_graybox(2210)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	cs.dev_spawn_enemy(1, 3)
	cs.dev_spawn_enemy(1, 4)
	for e in cs.enemies:
		e.hp = 50
		e.max_hp = 50
	cs.dev_force_load([
		FireResolver.ID_ARMOR_PIERCE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var sorted: Array = cs.enemies_sorted_by_cell()
	var hp0: Array[int] = [sorted[0].hp, sorted[1].hp, sorted[2].hp, sorted[3].hp]
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	# base 3 → 3/2/1/0（第4只不吃伤）
	assert_eq(hp0[0] - sorted[0].hp, 3)
	assert_eq(hp0[1] - sorted[1].hp, 2)
	assert_eq(hp0[2] - sorted[2].hp, 1)
	assert_eq(hp0[3] - sorted[3].hp, 0)
	assert_true(cs.last_shot_was_pierce)
	assert_true(_log_has(cs, "枪口【穿甲】"))
	assert_true("穿甲" in cs.muzzle_status_parts())


func test_muzzle_armor_pierce_applies_to_later_whites() -> void:
	## 挂枪口后，后续白弹也能递减穿怪（匣内留弹，避免末发进怪回合叠流血干扰断言）。
	var cs := CombatState.new(2211)
	cs.start_graybox(2211)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	cs.dev_spawn_enemy(1, 3)
	for e in cs.enemies:
		e.hp = 80
		e.max_hp = 80
	cs.dev_force_load([
		FireResolver.ID_ARMOR_PIERCE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var sorted: Array = cs.enemies_sorted_by_cell()
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())  # 穿甲 3/2/1
	assert_true(cs._muzzle_pierce)
	var hp_w0: Array[int] = [sorted[0].hp, sorted[1].hp, sorted[2].hp]
	assert_true(cs.fire_next_shot())  # 白弹底伤3 + 枪口穿甲 → 3/2/1
	assert_eq(hp_w0[0] - sorted[0].hp, 3)
	assert_eq(hp_w0[1] - sorted[1].hp, 2)
	assert_eq(hp_w0[2] - sorted[2].hp, 1)


func test_armor_pierce_muzzle_max_one_layer() -> void:
	## 最多 1 层：连打两发穿甲仍为布尔挂载，不叠层。
	var cs := CombatState.new(2212)
	cs.start_graybox(2212)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		FireResolver.ID_ARMOR_PIERCE,
		FireResolver.ID_ARMOR_PIERCE,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.begin_fire())
	assert_true(cs.fire_next_shot())
	assert_true(cs._muzzle_pierce)
	assert_true(cs.fire_next_shot())
	assert_true(cs._muzzle_pierce)
	# tip 含穿甲说明
	assert_true("穿甲：" in cs.muzzle_damage_tip_text() or "穿甲" in cs.muzzle_damage_tip_text())


func test_armor_pierce_in_reward_choices_pool() -> void:
	var pool: Array[int] = []
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if DataRegistry.is_ammo_reward_eligible(aid):
			pool.append(aid)
	assert_true(FireResolver.ID_ARMOR_PIERCE in pool)
	assert_true(FireResolver.ID_SUPER_ROUND in pool)
	assert_false(FireResolver.ID_GHOST in pool)
	assert_false(FireResolver.ID_PIERCE in pool, "old pierce ammo stays retired")


func test_endless_win_keeps_armor_pierce() -> void:
	var cs := CombatState.new(2213)
	cs.start_graybox(2213, true, FireResolver.ID_WRATH)
	cs._bag_append(FireResolver.ID_ARMOR_PIERCE, false)
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
		if int(id) == FireResolver.ID_ARMOR_PIERCE:
			n += 1
	assert_eq(n, 1, "armor pierce must survive endless wave win")


func test_muzzle_clears_after_fire_session() -> void:
	var cs := CombatState.new(2214)
	cs.start_graybox(2214)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		FireResolver.ID_ARMOR_PIERCE,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.do_fire())
	assert_false(cs._muzzle_pierce, "pierce muzzle clears when fire session ends")
