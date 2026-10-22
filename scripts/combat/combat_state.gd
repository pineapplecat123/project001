class_name CombatState
## 战斗状态机：装填 → FIRE/ROLL/UNLOAD → 怪回合 → 胜负。

enum Phase {
	AWAIT_LOAD,
	AWAIT_ACTION,
	AWAIT_ROLL_PICK,
	ENEMY_TURN,
	WON,
	LOST,
}

signal phase_changed(phase: int)
signal log_line(text: String)
signal state_changed

var phase: int = Phase.AWAIT_LOAD
var player_hp: int = CombatConstants.PLAYER_MAX_HP
var player_max_hp: int = CombatConstants.PLAYER_MAX_HP
var bag: Array[int] = []
var discard: Array[int] = []
var magazine: Magazine = Magazine.new()
var enemies: Array = []  ## Array[EnemyInstance]
var turn_index: int = 0
var needs_reshuffle_next_load: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var last_log: PackedStringArray = PackedStringArray()


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func start_graybox(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	BulletEffectRegistry.ensure_defaults()
	player_max_hp = CombatConstants.PLAYER_MAX_HP
	player_hp = player_max_hp
	bag.clear()
	discard.clear()
	for _i in CombatConstants.STARTER_WHITE_COUNT:
		bag.append(CombatConstants.WHITE_AMMO_ID)
	_shuffle(bag)
	magazine = Magazine.new()
	enemies.clear()
	var def: Dictionary = DataRegistry.get_enemy(CombatConstants.CIVILIAN_ENEMY_ID)
	enemies.append(EnemyInstance.new(def, CombatConstants.BOARD_SIZE - 1))
	turn_index = 0
	needs_reshuffle_next_load = false
	last_log.clear()
	_set_phase(Phase.AWAIT_LOAD)
	_log("战斗开始：白色子弹 ×%d vs 平民。" % CombatConstants.STARTER_WHITE_COUNT)
	_emit()


func _set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(phase)


func _log(text: String) -> void:
	last_log.append(text)
	log_line.emit(text)


func _emit() -> void:
	state_changed.emit()


func _shuffle(arr: Array[int]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func alive_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.is_alive():
			out.append(e)
	return out


func front_enemy() -> EnemyInstance:
	var best: EnemyInstance = null
	for e in alive_enemies():
		if best == null or e.cell < best.cell:
			best = e
	return best


func occupied_cells() -> Dictionary:
	var occ := {}
	for e in alive_enemies():
		occ[e.cell] = e
	return occ


func can_load() -> bool:
	return phase == Phase.AWAIT_LOAD


func can_fire() -> bool:
	return phase == Phase.AWAIT_ACTION and not magazine.is_empty()


func can_unload() -> bool:
	return phase == Phase.AWAIT_ACTION and not magazine.is_empty()


func can_start_roll() -> bool:
	return phase == Phase.AWAIT_ACTION and magazine.loaded_count() >= 1


func do_load() -> bool:
	if not can_load():
		return false
	if needs_reshuffle_next_load:
		_reshuffle_discard_into_bag()
		needs_reshuffle_next_load = false
	var draw_n: int = mini(CombatConstants.MAGAZINE_SIZE, bag.size())
	var drawn: Array[int] = []
	for _i in draw_n:
		drawn.append(bag.pop_front())
	magazine.load_sequence(drawn)
	if bag.is_empty():
		needs_reshuffle_next_load = true
	turn_index += 1
	_log("第 %d 回合：装填 %d 发。" % [turn_index, drawn.size()])
	if drawn.is_empty():
		_log("弹药袋与弹夹皆空，无法行动。")
		# 仍进入行动相位，但只能空等——实际灰盒袋不会空到无弃牌；若空则直接判负防卡死
		if discard.is_empty():
			player_hp = 0
			_check_end_after_player()
			_emit()
			return true
	_set_phase(Phase.AWAIT_ACTION)
	_emit()
	return true


func _reshuffle_discard_into_bag() -> void:
	for id in discard:
		bag.append(id)
	discard.clear()
	_shuffle(bag)
	_log("弃牌堆洗回弹药袋（%d 发）。" % bag.size())


func do_fire() -> bool:
	if not can_fire():
		return false
	var order: Array[int] = magazine.fire_order()
	var total := 0
	for ammo_id in order:
		var dmg: int = BulletEffectRegistry.compute_damage(ammo_id, {})
		var target: EnemyInstance = front_enemy()
		if target == null:
			_log("无可击中目标，余弹未造成伤害。")
			break
		var dealt: int = target.apply_hit(dmg)
		total += dealt
		_log("击发[%s] → %s 格%d 伤害%d（HP %d/%d）" % [
			DataRegistry.get_ammo(ammo_id).get("name", str(ammo_id)),
			target.name_zh, target.cell, dealt, target.hp, target.max_hp
		])
	for id in order:
		discard.append(id)
	magazine.clear()
	_log("射击结算完毕，总伤害 %d。" % total)
	if _check_end_after_player():
		_emit()
		return true
	_run_enemy_turn()
	_emit()
	return true


func begin_roll() -> bool:
	if not can_start_roll():
		return false
	if magazine.loaded_count() <= 1:
		# 单发无需挑选，直接结束回合
		_log("重 roll：仅 1 发，起点不变，结束回合。")
		_set_phase(Phase.AWAIT_ACTION)
		if _check_end_after_player():
			_emit()
			return true
		_run_enemy_turn()
		_emit()
		return true
	_set_phase(Phase.AWAIT_ROLL_PICK)
	_log("重 roll：点击弹夹一格作为新起点。")
	_emit()
	return true


func confirm_roll_start(slot_index: int) -> bool:
	if phase != Phase.AWAIT_ROLL_PICK:
		return false
	if slot_index < 0 or slot_index >= magazine.size():
		return false
	if magazine.slots[slot_index] == Magazine.EMPTY:
		return false
	magazine.set_start(slot_index)
	_log("重 roll：新起点 = 槽 %d。" % slot_index)
	if _check_end_after_player():
		_emit()
		return true
	_run_enemy_turn()
	_emit()
	return true


func do_unload() -> bool:
	if not can_unload():
		return false
	var removed: Array[int] = magazine.unload_all()
	for id in removed:
		discard.append(id)
	_log("卸除 %d 发进入弃牌堆。" % removed.size())
	if _check_end_after_player():
		_emit()
		return true
	_run_enemy_turn()
	_emit()
	return true


func _check_end_after_player() -> bool:
	_remove_dead()
	if alive_enemies().is_empty():
		_set_phase(Phase.WON)
		_log("胜利：敌人全灭。")
		return true
	if player_hp <= 0:
		_set_phase(Phase.LOST)
		_log("失败：玩家血量归零，整局结束。")
		return true
	return false


func _remove_dead() -> void:
	var kept: Array = []
	for e in enemies:
		if e.is_alive():
			kept.append(e)
		else:
			_log("%s 被击败。" % e.name_zh)
	enemies = kept


func _run_enemy_turn() -> void:
	_set_phase(Phase.ENEMY_TURN)
	_log("--- 怪物回合 ---")
	# 按离玩家从近到远移动，避免互相卡住时顺序不稳
	var order: Array = alive_enemies()
	order.sort_custom(func(a, b): return a.cell < b.cell)
	for e in order:
		_move_enemy(e)
		if e.cell == CombatConstants.PLAYER_CELL + 1:
			player_hp = maxi(0, player_hp - e.atk)
			_log("%s 攻击玩家，造成 %d（玩家 HP %d/%d）" % [e.name_zh, e.atk, player_hp, player_max_hp])
	# 流血 stub：不扣血，仅保留 stacks
	if player_hp <= 0:
		_set_phase(Phase.LOST)
		_log("失败：玩家血量归零，整局结束。")
		return
	if alive_enemies().is_empty():
		_set_phase(Phase.WON)
		_log("胜利：敌人全灭。")
		return
	_set_phase(Phase.AWAIT_LOAD)
	_log("--- 请装填 ---")


func _move_enemy(e: EnemyInstance) -> void:
	var steps: int = e.mobility
	var occ := occupied_cells()
	for _s in steps:
		var next_cell: int = e.cell - 1
		if next_cell <= CombatConstants.PLAYER_CELL:
			break
		if occ.has(next_cell):
			break
		occ.erase(e.cell)
		e.cell = next_cell
		occ[e.cell] = e
	_log("%s 移动至格 %d。" % [e.name_zh, e.cell])


func phase_name() -> String:
	match phase:
		Phase.AWAIT_LOAD:
			return "等待装填"
		Phase.AWAIT_ACTION:
			return "选择行动"
		Phase.AWAIT_ROLL_PICK:
			return "选择 ROLL 起点"
		Phase.ENEMY_TURN:
			return "怪物回合"
		Phase.WON:
			return "胜利"
		Phase.LOST:
			return "失败"
		_:
			return "未知"
