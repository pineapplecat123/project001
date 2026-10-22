class_name CombatState
## 战斗状态机。Push B：全弹药效果接入；敌人仍以平民为主。

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
var enemies: Array = []
var turn_index: int = 0
var needs_reshuffle_next_load: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var last_log: PackedStringArray = PackedStringArray()
var lose_reason: int = LoseReason.NONE
var gold: int = 0

## 弹药跨回合状态
var pink_bonus: int = 0
var last_load_ids: Array[int] = []  ## 上次装填原始序列（变形前），供黑白弹药

## 逐步射击会话
var _fire_queue: Array[int] = []
var _fire_damages: Array[int] = []
var _fire_index: int = 0
var _fire_total_damage: int = 0
var _carry_pierce: bool = false
var _carry_gas: bool = false
var _carry_fire: bool = false
var _carry_water: bool = false
var _carry_thunder: bool = false
var _pending_gold_autofires: int = 0


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
	pink_bonus = 0
	last_load_ids.clear()
	_reset_fire_session()
	_pending_gold_autofires = 0
	_set_phase(Phase.AWAIT_LOAD)
	_log("战斗开始：白色子弹 ×%d vs 平民。（可用开发者工具加入其它弹药）" % CombatConstants.STARTER_WHITE_COUNT)
	_emit()


func _reset_fire_session() -> void:
	_fire_queue.clear()
	_fire_damages.clear()
	_fire_index = 0
	_fire_total_damage = 0
	_carry_pierce = false
	_carry_gas = false
	_carry_fire = false
	_carry_water = false
	_carry_thunder = false


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


func enemies_sorted_by_cell() -> Array:
	var out: Array = alive_enemies()
	out.sort_custom(func(a, b): return a.cell < b.cell)
	return out


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
	var prev_load: Array[int] = last_load_ids.duplicate()
	var resolved: Array[int] = _resolve_black_white_with_prev(drawn, prev_load)
	last_load_ids = drawn.duplicate()
	magazine.load_sequence(resolved)
	if bag.is_empty():
		needs_reshuffle_next_load = true
	turn_index += 1
	_log("第 %d 回合：装填 %d 发。" % [turn_index, resolved.size()])
	for i in resolved.size():
		if drawn[i] == FireResolver.ID_BW and resolved[i] != FireResolver.ID_BW:
			_log("黑白子弹变形为 %s。" % DataRegistry.get_ammo(resolved[i]).get("name", resolved[i]))
	if resolved.is_empty():
		_log("弹药袋与弹夹皆空，无法行动。")
		if discard.is_empty() and magazine.is_empty():
			_lose_ammo_exhausted()
			_emit()
			return true
	_set_phase(Phase.AWAIT_ACTION)
	_emit()
	return true


func _resolve_black_white_with_prev(drawn: Array[int], prev_load: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for id in drawn:
		if id != FireResolver.ID_BW:
			out.append(id)
			continue
		if prev_load.is_empty():
			out.append(id)  # 不生效
			_log("黑白子弹：无上次装填，不变形。")
		else:
			var choice: int = FireResolver.most_common_ids(prev_load, rng)
			if choice < 0 or choice == FireResolver.ID_BW:
				out.append(id)
			else:
				out.append(choice)
	return out


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


func begin_fire() -> bool:
	if not can_fire():
		return false
	_reset_fire_session()
	_fire_queue = magazine.fire_order()
	_fire_damages = FireResolver.compute_shot_damages(_fire_queue, pink_bonus)
	_fire_index = 0
	_set_phase(Phase.FIRING)
	_log("开始射击（共 %d 发）…" % _fire_queue.size())
	if FireResolver.black_triggers(_fire_queue):
		_log("黑色弹药触发：本匣全伤害 ×3。")
	if FireResolver.blue_doubles_all(_fire_queue):
		_log("蓝色弹药触发：6 种不同 → 本匣全伤害 ×2。")
	_emit()
	return true


func fire_next_shot() -> bool:
	if phase != Phase.FIRING:
		return false
	if _fire_index >= _fire_queue.size():
		_finish_fire()
		return false
	var ammo_id: int = _fire_queue[_fire_index]
	var base_dmg: int = _fire_damages[_fire_index]
	_consume_hammer_chamber(ammo_id)

	var flags := FireResolver.inherits_from(ammo_id)
	var pierce := _carry_pierce or bool(flags["pierce"])
	var gas := _carry_gas or bool(flags["gas"])
	var fire := _carry_fire or bool(flags["fire"])
	var water := _carry_water or bool(flags["water"])
	var thunder := _carry_thunder or bool(flags["thunder"])

	var dealt_total := _apply_shot_to_enemies(ammo_id, base_dmg, pierce, gas, fire, water, thunder)
	_fire_total_damage += dealt_total
	discard.append(ammo_id)

	# 传给下一发：本发自带的效果
	_carry_pierce = bool(flags["pierce"])
	_carry_gas = bool(flags["gas"])
	_carry_fire = bool(flags["fire"])
	_carry_water = bool(flags["water"])
	_carry_thunder = bool(flags["thunder"])

	if ammo_id == FireResolver.ID_GOLD:
		_pending_gold_autofires += 1

	_fire_index += 1
	_remove_dead()
	_emit()
	if _fire_index >= _fire_queue.size():
		_finish_fire()
		return false
	return true


func _apply_shot_to_enemies(
	ammo_id: int, base_dmg: int, pierce: bool, gas: bool, fire: bool, water: bool, thunder: bool
) -> int:
	var targets: Array = enemies_sorted_by_cell()
	if targets.is_empty():
		_log("击发[%s] → 无可击中目标。" % _ammo_name(ammo_id))
		return 0
	var total := 0
	if pierce:
		var dmg := base_dmg
		for e in targets:
			if dmg <= 0:
				break
			total += _hit_enemy_with_elements(e, dmg, ammo_id, gas, fire, water, thunder)
			dmg -= 1
	else:
		var e: EnemyInstance = targets[0]
		total += _hit_enemy_with_elements(e, base_dmg, ammo_id, gas, fire, water, thunder)
		if thunder and e.wet_stacks > 0:
			total += _thunder_chain(e, base_dmg, gas, fire, water)
	return total


func _hit_enemy_with_elements(
	e: EnemyInstance, dmg: int, ammo_id: int, gas: bool, fire: bool, water: bool, thunder: bool
) -> int:
	var dealt: int = e.apply_hit(dmg)
	_log("击发[%s] → %s 格%d 伤害%d（HP %d/%d）%s" % [
		_ammo_name(ammo_id), e.name_zh, e.cell, dealt, e.hp, e.max_hp,
		(" " + e.status_text()) if e.status_text() != "" else ""
	])
	if not e.is_alive():
		return dealt
	# 水：湿，覆盖燃烧
	if water:
		e.wet_stacks = maxi(e.wet_stacks, dealt if dealt > 0 else dmg)
		e.burn_stacks = 0
		_log("  → 施加湿 %d（燃烧被覆盖）" % e.wet_stacks)
	# 汽油
	if gas:
		if e.burn_stacks > 0:
			var bonus := e.gas_stacks + (dealt if dealt > 0 else dmg)
			# 已燃烧时，本应施加的汽油直接转化为伤害
			var convert := dealt if dealt > 0 else dmg
			var extra: int = e.apply_hit(convert)
			dealt += extra
			_log("  → 已燃烧，汽油转化为伤害 %d" % extra)
		else:
			var add := dealt if dealt > 0 else dmg
			e.gas_stacks += add
			_log("  → 汽油 +%d（现 %d）" % [add, e.gas_stacks])
	# 火：点燃汽油链 + 燃烧
	if fire:
		if e.gas_stacks > 0 or _any_gas_adjacent_cluster(e):
			_ignite_gas_cluster(e)
		var burn_add := dealt if dealt > 0 else dmg
		e.burn_stacks += burn_add
		_log("  → 燃烧 +%d（现 %d）" % [burn_add, e.burn_stacks])
	return dealt


func _any_gas_adjacent_cluster(start: EnemyInstance) -> bool:
	return start.gas_stacks > 0


func _ignite_gas_cluster(start: EnemyInstance) -> void:
	## 所有与 start 通过相邻格子连在一起的带汽油敌人同时点燃。
	var by_cell := occupied_cells()
	var stack: Array = [start]
	var seen := {}
	while not stack.is_empty():
		var e: EnemyInstance = stack.pop_back()
		if seen.has(e):
			continue
		seen[e] = true
		if e.gas_stacks <= 0:
			continue
		var g := e.gas_stacks
		var boom: int = e.apply_hit(g)
		e.burn_stacks += g
		e.gas_stacks = 0
		_log("  → %s 汽油引爆伤害%d，燃烧%d" % [e.name_zh, boom, e.burn_stacks])
		for dc in [-1, 1]:
			var nc: int = e.cell + dc
			if by_cell.has(nc):
				var other: EnemyInstance = by_cell[nc]
				if other.gas_stacks > 0 and not seen.has(other):
					stack.append(other)


func _thunder_chain(origin: EnemyInstance, dmg: int, gas: bool, fire: bool, water: bool) -> int:
	var by_cell := occupied_cells()
	var visited := {}
	visited[origin] = true
	var total := 0
	var queue: Array = [origin]
	while not queue.is_empty():
		var cur: EnemyInstance = queue.pop_front()
		for dc in [-1, 1]:
			var nc: int = cur.cell + dc
			if not by_cell.has(nc):
				continue
			var other: EnemyInstance = by_cell[nc]
			if visited.has(other):
				continue
			if other.wet_stacks <= 0:
				continue
			visited[other] = true
			total += _hit_enemy_with_elements(other, dmg, FireResolver.ID_THUNDER, gas, fire, water, false)
			queue.append(other)
	return total


func _ammo_name(ammo_id: int) -> String:
	return str(DataRegistry.get_ammo(ammo_id).get("name", str(ammo_id)))


func _consume_hammer_chamber(expected_id: int) -> void:
	if magazine.is_empty():
		return
	var i := magazine.start_index
	var seen := 0
	while seen < magazine.size():
		if magazine.slots[i] == expected_id:
			magazine.slots[i] = Magazine.EMPTY
			break
		i = (i + 1) % magazine.size()
		seen += 1
	if magazine.is_empty():
		magazine.start_index = 0
		return
	var j := magazine.start_index % magazine.size()
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
	_reset_fire_session()
	# 金色：当前玩家回合内额外装填并自动射击（不跳过怪回合）
	while _pending_gold_autofires > 0 and not _check_end_after_player():
		_pending_gold_autofires -= 1
		_log("金色弹药：额外自动装填射击（剩余 %d）" % _pending_gold_autofires)
		if not _auto_load_and_fire_once():
			break
	_pending_gold_autofires = 0
	if _check_end_after_player():
		_emit()
		return
	_run_enemy_turn()
	_emit()


func _auto_load_and_fire_once() -> bool:
	## 金色额外轮：从袋抽满匣并立刻同步打完（无 UI 延迟）。
	if needs_reshuffle_next_load:
		_reshuffle_discard_into_bag()
		needs_reshuffle_next_load = false
	if bag.is_empty() and not discard.is_empty():
		_reshuffle_discard_into_bag()
	var draw_n: int = mini(CombatConstants.MAGAZINE_SIZE, bag.size())
	if draw_n <= 0:
		_log("金色额外轮：无弹药可装。")
		return false
	var drawn: Array[int] = []
	for _i in draw_n:
		drawn.append(bag.pop_front())
	var prev := last_load_ids.duplicate()
	last_load_ids = drawn.duplicate()
	var resolved := _resolve_black_white_with_prev(drawn, prev)
	magazine.load_sequence(resolved)
	if bag.is_empty():
		needs_reshuffle_next_load = true
	_reset_fire_session()
	_fire_queue = magazine.fire_order()
	_fire_damages = FireResolver.compute_shot_damages(_fire_queue, pink_bonus)
	_set_phase(Phase.FIRING)
	while _fire_index < _fire_queue.size():
		# 同步打完；金色嵌套再累加 pending
		var ammo_id: int = _fire_queue[_fire_index]
		var base_dmg: int = _fire_damages[_fire_index]
		_consume_hammer_chamber(ammo_id)
		var flags := FireResolver.inherits_from(ammo_id)
		var pierce := _carry_pierce or bool(flags["pierce"])
		var gas := _carry_gas or bool(flags["gas"])
		var fire := _carry_fire or bool(flags["fire"])
		var water := _carry_water or bool(flags["water"])
		var thunder := _carry_thunder or bool(flags["thunder"])
		_fire_total_damage += _apply_shot_to_enemies(ammo_id, base_dmg, pierce, gas, fire, water, thunder)
		discard.append(ammo_id)
		_carry_pierce = bool(flags["pierce"])
		_carry_gas = bool(flags["gas"])
		_carry_fire = bool(flags["fire"])
		_carry_water = bool(flags["water"])
		_carry_thunder = bool(flags["thunder"])
		if ammo_id == FireResolver.ID_GOLD:
			_pending_gold_autofires += 1
		_fire_index += 1
		_remove_dead()
	magazine.clear()
	_log("金色额外轮射击完毕。")
	_reset_fire_session()
	return true


func do_fire() -> bool:
	if not begin_fire():
		return false
	while phase == Phase.FIRING:
		fire_next_shot()
	return true


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
	var had_pink := false
	for id in removed:
		discard.append(id)
		if id == FireResolver.ID_PINK:
			had_pink = true
	if had_pink:
		pink_bonus += 1
		_log("粉色弹药卸除：本局粉色伤害永久 +1（现 +%d）。" % pink_bonus)
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
	# 燃烧跳伤
	for e in alive_enemies():
		if e.burn_stacks > 0:
			var b: int = e.burn_stacks
			var dealt: int = e.apply_hit(b)
			e.burn_stacks = maxi(0, e.burn_stacks - 1)
			_log("%s 燃烧结算伤害%d，燃烧剩余%d" % [e.name_zh, dealt, e.burn_stacks])
	_remove_dead()
	if alive_enemies().is_empty():
		_set_phase(Phase.WON)
		_log("胜利：敌人全灭。")
		return
	var order: Array = enemies_sorted_by_cell()
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


# ——— 开发者工具 ———

func dev_add_ammo(ammo_id: int, count: int = 1) -> void:
	for _i in count:
		bag.append(ammo_id)
	_log("[开发] 弹药袋 +%d × %s（现 %d）" % [count, _ammo_name(ammo_id), bag.size()])
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
	_log("[开发] 移除 %s 后袋内 %d" % [_ammo_name(ammo_id), bag.size()])
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
	_log("[开发] 金币 %+d → %d" % [amount, gold])
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
	var prev := last_load_ids.duplicate()
	last_load_ids = ids.duplicate()
	var resolved := _resolve_black_white_with_prev(ids, prev)
	magazine.load_sequence(resolved)
	turn_index += 1
	_set_phase(Phase.AWAIT_ACTION)
	_log("[开发] 强制装填 %s" % str(resolved))
	_emit()


func dev_skip_enemy_turn() -> void:
	if phase == Phase.FIRING:
		_log("[开发] 射击中不可跳过")
		return
	_set_phase(Phase.AWAIT_LOAD)
	_log("[开发] 跳过怪物回合 → 请装填")
	_emit()


func dev_spawn_enemy(enemy_id: int, cell: int = -1) -> void:
	var def: Dictionary = DataRegistry.get_enemy(enemy_id)
	if def.is_empty():
		_log("[开发] 未知敌人 id=%d" % enemy_id)
		return
	var c := cell
	if c < 0:
		c = CombatConstants.BOARD_SIZE - 1
		while occupied_cells().has(c) and c > CombatConstants.PLAYER_CELL + 1:
			c -= 1
	if occupied_cells().has(c) or c <= CombatConstants.PLAYER_CELL:
		_log("[开发] 无法在格 %d 生成" % c)
		return
	enemies.append(EnemyInstance.new(def, c))
	_log("[开发] 生成 %s 于格 %d" % [def.get("name", enemy_id), c])
	_emit()
