extends GutTest
## 战斗骨架：抽弹、roll、白弹扣血、平民移动攻击。


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
	# 验证起点偏移：放入可区分 id
	mag.load_sequence([10, 11, 12, 13, 14, 15] as Array[int])
	mag.set_start(3)
	assert_eq(mag.fire_order(), [13, 14, 15, 10, 11, 12])


func test_magazine_roll_rotate_relative_order() -> void:
	var mag := Magazine.new()
	mag.load_sequence([1, 2, 3, 4, 5, 6] as Array[int])
	mag.set_start(0)
	mag.rotate_start_forward()
	assert_eq(mag.start_index, 1)
	assert_eq(mag.fire_order(), [2, 3, 4, 5, 6, 1])


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
	var hp_before := enemy.hp
	assert_true(cs.do_fire())
	# 6 发白弹 ×3 = 18，平民 10 HP → 应被击败，战斗胜利
	assert_eq(cs.phase, CombatState.Phase.WON)
	assert_lt(hp_before, 999)  # sanity
	assert_true(cs.alive_enemies().is_empty())


func test_roll_then_enemy_advances() -> void:
	var cs := CombatState.new(99)
	cs.start_graybox(99)
	# 加厚敌人血量，避免被其它路径误杀；本测只 ROLL
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	var start_cell: int = cs.enemies[0].cell
	cs.do_load()
	assert_true(cs.begin_roll())
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ROLL_PICK)
	assert_true(cs.confirm_roll_start(2))
	assert_eq(cs.magazine.start_index, 2)
	# ROLL 耗回合 → 怪移动 1 格
	assert_eq(cs.enemies[0].cell, start_cell - 1)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)


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


func test_civilian_attacks_when_adjacent() -> void:
	var cs := CombatState.new(1)
	cs.start_graybox(1)
	cs.enemies[0].hp = 100
	cs.enemies[0].cell = 2  # 移动 1 格后到 1，与玩家相邻
	var hp_before := cs.player_hp
	cs.do_load()
	cs.do_unload()  # 耗回合进怪回合
	assert_eq(cs.enemies[0].cell, 1)
	assert_eq(cs.player_hp, hp_before - cs.enemies[0].atk)


func test_white_bullet_damage_value() -> void:
	assert_eq(BulletEffectRegistry.compute_damage(CombatConstants.WHITE_AMMO_ID), 3)
