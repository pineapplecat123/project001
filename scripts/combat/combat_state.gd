class_name CombatState
## 战斗状态机：装填 → FIRE/ROLL/UNLOAD → 怪回合 → 胜负。
## FIRE 支持逐步击发（UI 控制节奏）；ROLL 为随机转轮。

enum Phase {
	AWAIT_LOAD,
	AWAIT_ACTION,
	FIRING,
	ENEMY_TURN,
	WON,
	LOST,
}

enum LoseReason {
	NONE,
	HP,
	AMMO_EXHAUSTED,
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
var lose_reason: int = LoseReason.NONE
var gold: int = 0  ## 经济 stub，供开发者工具

## 逐步射击会话
var _fire_queue: Array[int] = []
var _fire_total_damage: int = 0


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
	lose_reason = LoseReason.NONE
	gold = 0
	_fire_queue.clear()
	_fire_total_damage = 0
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


func is_adjacent_to_player(e: EnemyInstance) -> bool:
	return e != null and e.is_alive() and e.cell == CombatConstants.PLAYER_CELL + 1


func can_load() -> bool:
	return phase == Phase.AWAIT_LOAD


func can_fire() -> bool:
	return phase == Phase.AWAIT_ACTION and not magazine.is_empty()


func can_unload() -> bool:
	return phase == Phase.AWAIT_ACTION and not magazine.is_empty()


func can_start_roll() -> bool:
	return phase == Phase.AWAIT_ACTION and magazine.loaded_count() >= 1


func is_busy_firing() -> bool:
	return phase == Phase.FIRING


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
		if discard.is_empty() and magazine.is_empty():
			# 弹药耗尽：失败，但不伪装成被怪打死（不清零 HP）
			_lose_ammo_exhausted()
			_emit()
			return true
	_set_phase(Phase.AWAIT_ACTION)
	_emit()
	return true


func _lose_ammo_exhausted() -> void:
	lose_reason = LoseReason.AMMO_EXHAUSTED
	_set_phase(Phase.LOST)
	_log("失败：弹药耗尽（并非被怪物击杀）。")


func _lose_hp() -> void:
	lose_reason = LoseReason.HP
	_set_phase(Phase.LOST)
	_log("失败：玩家血量归零，整局结束。")


func _reshuffle_discard_into_bag() -> void:
	for id in discard:
		bag.append(id)
	discard.clear()
	_shuffle(bag)
	_log("弃牌堆洗回弹药袋（%d 发）。" % bag.size())


## 开始逐步射击；之后由 UI 反复调用 fire_next_shot()。
func begin_fire() -> bool:
	if not can_fire():
		return false
	_fire_queue = magazine.fire_order()
	_fire_total_damage = 0
	# 弹夹视觉：击发过程中逐发清空对准锤位的槽
	_set_phase(Phase.FIRING)
	_log("开始射击（共 %d 发）…" % _fire_queue.size())
	_emit()
	return true


## 结算下一发；返回 true 表示还有后续发次。全部打完后自动收尾并进入怪回合（或胜负）。
func fire_next_shot() -> bool:
	if phase != Phase.FIRING:
		return false
	if _fire_queue.is_empty():
		_finish_fire()
		return false
	var ammo_id: int = _fire_queue.pop_front()
	# 从转轮锤位卸掉当前发（保持环形相对顺序的视觉：推进 start）
	_consume_hammer_chamber(ammo_id)
	var dmg: int = BulletEffectRegistry.compute_damage(ammo_id, {})
	var target: EnemyInstance = front_enemy()
	if target == null:
		_log("击发[%s] → 无可击中目标。" % DataRegistry.get_ammo(ammo_id).get("name", str(ammo_id)))
		discard.append(ammo_id)
		_emit()
		if _fire_queue.is_empty():
			_finish_fire()
			return false
		return true
	var dealt: int = target.apply_hit(dmg)
	_fire_total_damage += dealt
	_log("击发[%s] → %s 格%d 伤害%d（HP %d/%d）" % [
		DataRegistry.get_ammo(ammo_id).get("name", str(ammo_id)),
		target.name_zh, target.cell, dealt, target.hp, target.max_hp
	])
	discard.append(ammo_id)
	_remove_dead()
	_emit()
	if _fire_queue.is_empty():
		_finish_fire()
		return false
	return true


func _consume_hammer_chamber(expected_id: int) -> void:
	## 锤位（start_index）应对准本发；打完后该槽变空，start 转到下一非空（若还有）。
	if magazine.is_empty():
		return
	var i := magazine.start_index
	# 找到 expected（通常就是 start）
	var seen := 0
	while seen < magazine.size():
		if magazine.slots[i] == expected_id:
			magazine.slots[i] = Magazine.EMPTY
			break
		i = (i + 1) % magazine.size()
		seen += 1
	# 将 start 挪到下一个仍装填的槽（保持击发顺序视觉）
	if magazine.is_empty():
		magazine.start_index = 0
		return
	var j := (magazine.start_index) % magazine.size()
	seen = 0
	while seen < magazine.size():
		if magazine.slots[j] != Magazine.EMPTY:
			magazine.start_index = j
			return
		j = (j + 1) % magazine.size()
		seen += 1


func _finish_fire() -> void:
	magazine.clear()
	_log("射击结算完毕，总伤害 %d。" % _fire_total_damage)
	_fire_queue.clear()
	if _check_end_after_player():
		_emit()
		return
	_run_enemy_turn()
	_emit()


## 同步一键打完（测试用，无延迟）。
func do_fire() -> bool:
	if not begin_fire():
		return false
	while phase == Phase.FIRING:
		fire_next_shot()
	return true


## ROLL：随机转动转轮（击发点固定），耗玩家回合后进入怪回合。
func begin_roll() -> bool:
	if not can_start_roll():
		return false
	var before := magazine.start_index
	var steps: int = magazine.random_roll(rng)
	if magazine.loaded_count() <= 1:
		_log("重 roll：仅 %d 发，转轮不转（步数 0）。" % magazine.loaded_count())
	else:
		_log("重 roll：转轮转动 %d 步（击发点固定）。起点槽 %d → %d。" % [
			steps, before, magazine.start_index
		])
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
		_lose_hp()
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
	var order: Array = alive_enemies()
	order.sort_custom(func(a, b): return a.cell < b.cell)
	for e in order:
		_move_enemy(e)
		if is_adjacent_to_player(e):
			player_hp = maxi(0, player_hp - e.atk)
			_log("%s 攻击玩家，造成 %d（玩家 HP %d/%d）" % [e.name_zh, e.atk, player_hp, player_max_hp])
		else:
			_log("%s 未邻接，不攻击（格 %d）。" % [e.name_zh, e.cell])
	if player_hp <= 0:
		_lose_hp()
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
		Phase.FIRING:
			return "射击中"
		Phase.ENEMY_TURN:
			return "怪物回合"
		Phase.WON:
			return "胜利"
		Phase.LOST:
			return "失败"
		_:
			return "未知"


# ——— 开发者工具（骨架） ———

func dev_add_ammo(ammo_id: int, count: int = 1) -> void:
	for _i in count:
		bag.append(ammo_id)
	_log("[开发] 弹药袋 +%d × id=%d（现 %d）" % [count, ammo_id, bag.size()])
	_emit()


func dev_remove_ammo(ammo_id: int, count: int = 1) -> void:
	var left := count
	var i := 0
	while i < bag.size() and left > 0:
		if bag[i] == ammo_id:
			bag.remove_at(i)
			left -= 1
		else:
			i += 1
	_log("[开发] 弹药袋移除 id=%d（剩余请求 %d）现 %d" % [ammo_id, left, bag.size()])
	_emit()


func dev_kill_all_enemies() -> void:
	for e in enemies:
		e.hp = 0
	_remove_dead()
	_log("[开发] 一键杀敌")
	if alive_enemies().is_empty():
		_set_phase(Phase.WON)
		_log("胜利：敌人全灭。")
	_emit()


func dev_add_gold(amount: int = 10) -> void:
	gold += amount
	_log("[开发] 金币 %+d → %d（经济 stub）" % [amount, gold])
	_emit()


func dev_set_player_hp(v: int) -> void:
	player_hp = clampi(v, 0, player_max_hp)
	_log("[开发] 玩家 HP → %d" % player_hp)
	if player_hp <= 0:
		_lose_hp()
	_emit()


func dev_set_front_enemy_hp(v: int) -> void:
	var e := front_enemy()
	if e == null:
		_log("[开发] 无敌人")
		return
	e.hp = clampi(v, 0, e.max_hp)
	_log("[开发] %s HP → %d" % [e.name_zh, e.hp])
	_remove_dead()
	_emit()


func dev_teleport_front_enemy(cell: int) -> void:
	var e := front_enemy()
	if e == null:
		_log("[开发] 无敌人")
		return
	var c := clampi(cell, CombatConstants.PLAYER_CELL + 1, CombatConstants.BOARD_SIZE - 1)
	var occ := occupied_cells()
	occ.erase(e.cell)
	if occ.has(c):
		_log("[开发] 格 %d 已占用" % c)
		return
	e.cell = c
	_log("[开发] %s 瞬移至格 %d" % [e.name_zh, e.cell])
	_emit()


func dev_force_load(ids: Array[int]) -> void:
	if phase != Phase.AWAIT_LOAD and phase != Phase.AWAIT_ACTION:
		_log("[开发] 当前阶段无法强制装填")
		return
	magazine.load_sequence(ids)
	turn_index += 1
	_set_phase(Phase.AWAIT_ACTION)
	_log("[开发] 强制装填 %s" % str(ids))
	_emit()


func dev_skip_enemy_turn() -> void:
	if phase == Phase.FIRING:
		_log("[开发] 射击中不可跳过")
		return
	_set_phase(Phase.AWAIT_LOAD)
	_log("[开发] 跳过怪物回合 → 请装填")
	_emit()
