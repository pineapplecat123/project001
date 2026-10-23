class_name CombatState
## 战斗状态机。清场后奖励三选一，结算后再下一波；ROLL/FIRE/UNLOAD 均结束玩家行动（怪前进）；LOAD 可逐步装填。ROLL 不清空弹匣：怪回合后若匣内仍有弹则回 AWAIT_ACTION。

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

enum EncounterKind {
	NORMAL,
	ELITE,
	BOSS,
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
var wave_index: int = 1

## 战斗胜利奖励（灰盒：基础金币 + 弹药三选一；可放弃换额外金）
var reward_pending: bool = false
var reward_resolved: bool = false
var reward_choices: Array[int] = []
## 预留钩子：本波是否受伤、本波玩家回合数（无伤/三回合奖励灰盒先不做）
var wave_took_damage: bool = false
var wave_player_turns: int = 0

## 是否来自地图 run（胜利领奖后回地图；练习战则下一波）
var from_map_run: bool = false
## 遭遇类型：普通 / 精英 / Boss（灰盒）
var encounter_kind: int = EncounterKind.NORMAL
## 本波实际发放的基础金币（供 UI 显示）
var last_reward_base_gold: int = 0

## 弹药跨回合状态
var pink_bonus: int = 0
var last_load_ids: Array[int] = []  ## 上次装填原始序列（变形前），供黑白弹药

## 逐步射击会话
var _fire_queue: Array[int] = []
var _fire_damages: Array[int] = []
var _fire_index: int = 0
var _fire_total_damage: int = 0
var _muzzle_pierce: bool = false
var _muzzle_gas: bool = false
var _muzzle_fire: bool = false
var _muzzle_water: bool = false
var _muzzle_thunder: bool = false
var _pending_gold_autofires: int = 0

## 逐步装填会话（UI：装一发→转 60°→再装；do_load 仍可一次装满）
var _load_session_active: bool = false
var _load_next_slot: int = 0
var _load_raw_ids: Array[int] = []
var _load_resolved_ids: Array[int] = []
## UI：上一发实际对准的仓位（锤位）；空仓也会记下
var last_fired_slot: int = -1
## UI：上一发是否空仓（无效果、无黄闪，仍推进一格）
var last_shot_was_blank: bool = false


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
	wave_index = 1
	_spawn_wave_enemies([CombatConstants.CIVILIAN_ENEMY_ID])
	turn_index = 0
	needs_reshuffle_next_load = false
	last_log.clear()
	lose_reason = LoseReason.NONE
	gold = 0
	pink_bonus = 0
	last_load_ids.clear()
	_reset_fire_session()
	_reset_muzzle()
	_pending_gold_autofires = 0
	_reset_load_session()
	_clear_reward_state()
	wave_took_damage = false
	wave_player_turns = 0
	from_map_run = false
	encounter_kind = EncounterKind.NORMAL
	last_reward_base_gold = 0
	_set_phase(Phase.AWAIT_LOAD)
	_log("战斗开始：白色弹药 ×%d · 第 %d 波。（可用开发者工具加入其它弹药）" % [
		CombatConstants.STARTER_WHITE_COUNT, wave_index
	])
	_emit()


## 从地图 Run 进入战斗：继承袋/金币/HP/粉成长；不重置构筑。
func start_from_run(payload: Dictionary, seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	elif int(payload.get("seed", 0)) != 0:
		rng.seed = int(payload["seed"])
	BulletEffectRegistry.ensure_defaults()
	from_map_run = true
	encounter_kind = _parse_encounter(str(payload.get("encounter", "normal")))
	last_reward_base_gold = 0
	player_max_hp = int(payload.get("player_max_hp", CombatConstants.PLAYER_MAX_HP))
	player_hp = int(payload.get("player_hp", player_max_hp))
	bag.clear()
	for x in payload.get("bag", []):
		bag.append(int(x))
	if bag.is_empty():
		for _i in CombatConstants.STARTER_WHITE_COUNT:
			bag.append(CombatConstants.WHITE_AMMO_ID)
	discard.clear()
	magazine = Magazine.new()
	enemies.clear()
	wave_index = 1
	_spawn_wave_enemies()
	turn_index = 0
	needs_reshuffle_next_load = false
	last_log.clear()
	lose_reason = LoseReason.NONE
	gold = int(payload.get("gold", 0))
	pink_bonus = int(payload.get("pink_bonus", 0))
	last_load_ids.clear()
	_reset_fire_session()
	_reset_muzzle()
	_pending_gold_autofires = 0
	_reset_load_session()
	_clear_reward_state()
	wave_took_damage = false
	wave_player_turns = 0
	if encounter_kind == EncounterKind.BOSS:
		_inject_invalid_ammo(CombatConstants.BOSS_INVALID_ON_START, "开场")
	_set_phase(Phase.AWAIT_LOAD)
	_log("地图%s：袋 %d · 金币 %d · HP %d · 第 %d 波。" % [
		encounter_label(), bag.size(), gold, player_hp, wave_index
	])
	_emit()


## 离开战斗回地图前：匣内/弃牌并回袋，导出 run 快照。
func export_run_payload() -> Dictionary:
	_consolidate_ammo_into_bag()
	var out_bag: Array[int] = []
	for id in bag:
		out_bag.append(id)
	return {
		"gold": gold,
		"bag": out_bag,
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"pink_bonus": pink_bonus,
	}


func _consolidate_ammo_into_bag() -> void:
	if not magazine.is_empty():
		for id in magazine.unload_all():
			bag.append(id)
	if not discard.is_empty():
		for id in discard:
			bag.append(id)
		discard.clear()



func _reset_fire_session() -> void:
	## 仅清射击队列；枪口效果跨金色额外轮保留，回合结束由 _reset_muzzle 清。
	_fire_queue.clear()
	_fire_damages.clear()
	_fire_index = 0
	_fire_total_damage = 0
	last_shot_was_blank = false
	last_fired_slot = -1


func _reset_muzzle() -> void:
	## 回合结束重置枪口：状态弹挂上的效果本回合内持续附带到后续击发。
	_muzzle_pierce = false
	_muzzle_gas = false
	_muzzle_fire = false
	_muzzle_water = false
	_muzzle_thunder = false


func _mount_muzzle_from(flags: Dictionary) -> void:
	## 射击过的状态效果挂到枪口（累积，不覆盖其它已挂效果）。
	if bool(flags.get("pierce", false)):
		_muzzle_pierce = true
	if bool(flags.get("gas", false)):
		_muzzle_gas = true
	if bool(flags.get("fire", false)):
		_muzzle_fire = true
	if bool(flags.get("water", false)):
		_muzzle_water = true
	if bool(flags.get("thunder", false)):
		_muzzle_thunder = true


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


## 检视用：按弹种汇总牌库拥有量（袋 + 膛 + 弃）。袋空时仍列出构筑内弹种。
func ammo_inventory_by_id() -> Dictionary:
	var out: Dictionary = {}
	for ammo_id in bag:
		var id: int = int(ammo_id)
		if not out.has(id):
			out[id] = {"bag": 0, "mag": 0, "discard": 0, "total": 0}
		out[id]["bag"] = int(out[id]["bag"]) + 1
		out[id]["total"] = int(out[id]["total"]) + 1
	if magazine != null:
		for ammo_id in magazine.slots:
			var id2: int = int(ammo_id)
			if id2 == Magazine.EMPTY:
				continue
			if not out.has(id2):
				out[id2] = {"bag": 0, "mag": 0, "discard": 0, "total": 0}
			out[id2]["mag"] = int(out[id2]["mag"]) + 1
			out[id2]["total"] = int(out[id2]["total"]) + 1
	for ammo_id in discard:
		var id3: int = int(ammo_id)
		if not out.has(id3):
			out[id3] = {"bag": 0, "mag": 0, "discard": 0, "total": 0}
		out[id3]["discard"] = int(out[id3]["discard"]) + 1
		out[id3]["total"] = int(out[id3]["total"]) + 1
	return out


## 弹药袋无顺序：每次从现存弹药中均匀随机抽取（数量加权=逐发随机下标），不按数组 FIFO。
func _draw_random_from_bag(count: int) -> Array[int]:
	var drawn: Array[int] = []
	var n: int = mini(count, bag.size())
	for _i in n:
		var idx: int = rng.randi_range(0, bag.size() - 1)
		drawn.append(bag[idx])
		bag.remove_at(idx)
	return drawn


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


## 敌人是否在其 attack_range 内可攻击玩家（精英/Boss 可 >1）。
func can_attack_player(e: EnemyInstance) -> bool:
	if e == null or not e.is_alive():
		return false
	var dist: int = e.cell - CombatConstants.PLAYER_CELL
	return dist >= 1 and dist <= e.attack_range


func _reset_load_session() -> void:
	_load_session_active = false
	_load_next_slot = 0
	_load_raw_ids.clear()
	_load_resolved_ids.clear()


func is_busy_loading() -> bool:
	return _load_session_active


func can_load() -> bool:
	return phase == Phase.AWAIT_LOAD and not _load_session_active


func can_fire() -> bool:
	return phase == Phase.AWAIT_ACTION and not magazine.is_empty()


func can_unload() -> bool:
	return phase == Phase.AWAIT_ACTION and not magazine.is_empty()


func can_start_roll() -> bool:
	return phase == Phase.AWAIT_ACTION and magazine.loaded_count() >= 1


func is_busy_firing() -> bool:
	return phase == Phase.FIRING


## 一次装满（测试 / 金色额外轮 / 无动画路径）。UI 请用 begin_load + load_next_chamber + apply_load_rotate。
## 装满后会自动 random_roll（与 UI 装满后的 reroll 动画一致）；不满匣不转。
func do_load() -> bool:
	if not begin_load():
		return false
	var needs_spin := false
	while _load_session_active:
		var r: Dictionary = load_next_chamber()
		needs_spin = bool(r.get("needs_spin", false))
		if not bool(r.get("done", false)) and bool(r.get("ok", false)):
			apply_load_rotate()
	if needs_spin:
		apply_roll()
	return true


## 开始逐步装填会话。成功后反复调用 load_next_chamber；每发写入后若未满，再 apply_load_rotate。
## 约定：start_index = 正上击发仓；上弹口=左上=(start+LOAD_PORT_OFFSET)%6。
## 下回合洗回：先归还膛内未耗弹（ROLL 后），再按标记/袋空把弃牌洗回袋；本回合仍能抽几发装几发。
func begin_load() -> bool:
	if not can_load():
		return false
	_return_magazine_to_bag()
	_reshuffle_if_needed_for_load()
	magazine.clear()
	_load_session_active = true
	_load_next_slot = 0
	_load_raw_ids.clear()
	_load_resolved_ids.clear()
	# 仓 0 对准左上上弹口
	magazine.start_index = CombatConstants.LOAD_SESSION_INITIAL_START
	turn_index += 1
	wave_player_turns += 1
	_log("第 %d 回合：开始装填（上弹口=左上，击发点=正上）…" % turn_index)
	_emit()
	if bag.is_empty():
		return _finish_load_session_empty()
	return true


## 装入当前上弹口（左上）那一仓。不立即转盘：UI 先展示入弹，再调用 apply_load_rotate。
## 返回：ok/done/ammo_id/slot/rotate_to/exhausted/needs_spin
## rotate_to = 下一步应转到的 start_index（未满时 = 当前+1）；done 时不转。
func load_next_chamber() -> Dictionary:
	var fail := {
		"ok": false,
		"done": true,
		"ammo_id": Magazine.EMPTY,
		"slot": -1,
		"rotate_to": magazine.start_index if magazine != null else 0,
		"exhausted": false,
		"needs_spin": false,
	}
	if not _load_session_active:
		return fail
	if _load_next_slot >= CombatConstants.MAGAZINE_SIZE or bag.is_empty():
		return _complete_load_session()
	var drawn: Array[int] = _draw_random_from_bag(1)
	var raw_id: int = drawn[0]
	_load_raw_ids.append(raw_id)
	var resolved_arr: Array[int] = _resolve_black_white_with_prev([raw_id], last_load_ids)
	var resolved: int = resolved_arr[0]
	_load_resolved_ids.append(resolved)
	var slot: int = magazine.chamber_at_load_port()
	magazine.set_slot(slot, resolved)
	if raw_id == FireResolver.ID_BW and resolved != FireResolver.ID_BW:
		_log("黑白子弹变形为 %s。" % _ammo_name(resolved))
	_log("装填上弹口→仓 %d：%s。" % [slot + 1, _ammo_name(resolved)])
	_load_next_slot += 1
	if bag.is_empty():
		needs_reshuffle_next_load = true
	var more: bool = _load_next_slot < CombatConstants.MAGAZINE_SIZE and not bag.is_empty()
	if more:
		var rotate_to: int = (magazine.start_index + 1) % CombatConstants.MAGAZINE_SIZE
		_emit()
		return {
			"ok": true,
			"done": false,
			"ammo_id": resolved,
			"slot": slot,
			"rotate_to": rotate_to,
			"exhausted": false,
			"needs_spin": false,
		}
	return _complete_load_session_after_shot(resolved, slot)


## 装弹入格展示完毕后调用：整盘逻辑步进 60°（start_index+1），供下一发对准上弹口。
func apply_load_rotate() -> int:
	if magazine == null:
		return 0
	magazine.start_index = (magazine.start_index + 1) % CombatConstants.MAGAZINE_SIZE
	_emit()
	return magazine.start_index


func _complete_load_session_after_shot(resolved: int, slot: int) -> Dictionary:
	var result := _complete_load_session()
	result["ammo_id"] = resolved
	result["slot"] = slot
	result["ok"] = true
	return result


func _complete_load_session() -> Dictionary:
	last_load_ids = _load_raw_ids.duplicate()
	var n: int = _load_resolved_ids.size()
	var needs_spin: bool = n >= CombatConstants.MAGAZINE_SIZE and not magazine.is_empty()
	_log("装填完成：共 %d 发%s。" % [
		n, "（将随机旋转转轮）" if needs_spin else ""
	])
	var rotate_to: int = magazine.start_index
	_reset_load_session()
	if magazine.is_empty():
		magazine.start_index = 0
		_log("弹药袋与弹夹皆空，无法行动。")
		if discard.is_empty():
			_lose_ammo_exhausted()
			_emit()
			return {
				"ok": true,
				"done": true,
				"ammo_id": Magazine.EMPTY,
				"slot": -1,
				"rotate_to": 0,
				"exhausted": true,
				"needs_spin": false,
			}
		# 弃牌仍有弹：标记下回合洗回，不因袋空判负
		needs_reshuffle_next_load = true
	_set_phase(Phase.AWAIT_ACTION)
	_emit()
	return {
		"ok": true,
		"done": true,
		"ammo_id": Magazine.EMPTY,
		"slot": -1,
		"rotate_to": rotate_to,
		"exhausted": false,
		"needs_spin": needs_spin,
	}


func _finish_load_session_empty() -> bool:
	_complete_load_session()
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
	## 仅当袋+弃+膛皆空且无法洗回时触发（正常对局袋空会在下回合洗回，不应走到这里）。
	lose_reason = LoseReason.AMMO_EXHAUSTED
	_set_phase(Phase.LOST)
	_log("失败：弹药耗尽（袋、弃牌与弹夹皆空，无法洗回）。")


## ROLL 不耗弹：下回合 LOAD 前把膛内剩余弹归还弹药袋（不进弃牌堆）。
func _return_magazine_to_bag() -> void:
	if magazine == null or magazine.is_empty():
		return
	var n := 0
	for id in magazine.slots:
		if id != Magazine.EMPTY:
			bag.append(id)
			n += 1
	magazine.clear()
	if n > 0:
		_log("膛内未耗 %d 发归还弹药袋。" % n)


## 下回合洗回：标记为真，或袋已空且弃牌有弹时，把弃牌洗混回袋。不在当回合装弹中途洗满。
func _reshuffle_if_needed_for_load() -> void:
	if needs_reshuffle_next_load or (bag.is_empty() and not discard.is_empty()):
		_reshuffle_discard_into_bag()
		needs_reshuffle_next_load = false


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
	# 锤位空仓：无效果、不耗队列发数；推进一格；UI 不黄闪
	var hammer: int = magazine.chamber_at_fire_port()
	last_fired_slot = hammer
	if magazine.slots[hammer] == Magazine.EMPTY:
		last_shot_was_blank = true
		_advance_cylinder_one_step()
		_log("击发[空仓] → 无效果。")
		_emit()
		# 队列里还有实弹则继续；否则收束（不应出现：有实弹待发却只剩空）
		if _fire_index >= _fire_queue.size() or magazine.is_empty():
			_finish_fire()
			return false
		return true

	last_shot_was_blank = false
	var ammo_id: int = _fire_queue[_fire_index]
	var base_dmg: int = _fire_damages[_fire_index]
	_consume_hammer_chamber(ammo_id)

	var flags := FireResolver.inherits_from(ammo_id)
	var pierce := _muzzle_pierce or bool(flags["pierce"])
	var gas := _muzzle_gas or bool(flags["gas"])
	var fire := _muzzle_fire or bool(flags["fire"])
	var water := _muzzle_water or bool(flags["water"])
	var thunder := _muzzle_thunder or bool(flags["thunder"])

	var dealt_total := _apply_shot_to_enemies(ammo_id, base_dmg, pierce, gas, fire, water, thunder)
	_fire_total_damage += dealt_total
	discard.append(ammo_id)

	# 本发状态效果挂上枪口，本回合后续击发都附带
	_mount_muzzle_from(flags)

	_fire_index += 1
	_remove_dead()

	# 金色：击发后立刻额外自动装填射击一轮（不拖到整匣打完，避免被同匣后续弹清场后跳过）
	# 「弹夹内有几发金就几轮」只计本匣击发的金，额外轮内的金不再叠加轮数。
	if ammo_id == FireResolver.ID_GOLD and not alive_enemies().is_empty():
		_log("金色弹药：额外自动装填射击")
		_auto_load_and_fire_once()
		_remove_dead()

	_emit()

	# 中途清场：立刻停射进胜利，未击发归袋
	if alive_enemies().is_empty():
		_abort_fire_cleared()
		return false

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
		var boom: int = e.apply_damage(g)
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
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		return CombatConstants.INVALID_AMMO_NAME
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	if def.is_empty():
		return "未知#%d" % ammo_id
	return str(def.get("name", str(ammo_id)))


func _advance_cylinder_one_step() -> void:
	## 转轮固定推进一格（60°）；空仓由 fire_next_shot 单独结算，不再跳过。
	if magazine == null or magazine.size() <= 0:
		return
	magazine.start_index = (magazine.start_index + 1) % magazine.size()


func _consume_hammer_chamber(expected_id: int) -> void:
	## 清空正上击发点那一仓，然后 start_index+1（固定转 60°）。空仓留给下一发明示结算。
	if magazine.is_empty():
		return
	var hammer: int = magazine.chamber_at_fire_port()
	if magazine.slots[hammer] == expected_id:
		magazine.slots[hammer] = Magazine.EMPTY
	else:
		# 兜底：自锤位起找第一发匹配（不应在逐步射满匣时触发）
		var i := hammer
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
	_advance_cylinder_one_step()


func _finish_fire() -> void:
	## 整匣打完（或无剩余实弹）后的收束。金色已在击发当发处理。
	magazine.clear()
	_log("射击结算完毕，总伤害 %d。" % _fire_total_damage)
	_reset_fire_session()
	_pending_gold_autofires = 0
	_reset_muzzle()  # 本回合射击结束，重置枪口
	if _check_end_after_player():
		_emit()
		return
	_run_enemy_turn()
	_emit()


func _abort_fire_cleared() -> void:
	## 连射中途敌人全灭：停射、未击发归袋、清枪口、进胜利（不跑怪回合）。
	var returned := 0
	if magazine != null and not magazine.is_empty():
		for id in magazine.slots:
			if id != Magazine.EMPTY:
				returned += 1
		_return_magazine_to_bag()
	_log("射击中途清场，未击发 %d 发归还弹药袋。总伤害 %d。" % [returned, _fire_total_damage])
	_reset_fire_session()
	_pending_gold_autofires = 0
	_reset_muzzle()
	_enter_won()
	_emit()


func _auto_load_and_fire_once() -> bool:
	## 金色额外轮：从袋抽满匣并立刻同步打完（无 UI 延迟）。枪口跨轮保留。
	## 额外轮内的金色不再叠加新轮（轮数=本匣击发金数）。中途清场则停并归还未击发。
	## 必须暂存主匣剩余弹，避免 load_sequence 冲掉尚未击发的主匣弹药。
	_reshuffle_if_needed_for_load()
	var draw_n: int = mini(CombatConstants.MAGAZINE_SIZE, bag.size())
	if draw_n <= 0:
		_log("金色额外轮：无弹药可装。")
		return false
	var saved_slots: Array[int] = magazine.slots.duplicate()
	var saved_start: int = magazine.start_index
	var saved_queue: Array[int] = _fire_queue.duplicate()
	var saved_damages: Array[int] = _fire_damages.duplicate()
	var saved_index: int = _fire_index
	var drawn: Array[int] = _draw_random_from_bag(draw_n)
	var prev := last_load_ids.duplicate()
	last_load_ids = drawn.duplicate()
	var resolved := _resolve_black_white_with_prev(drawn, prev)
	magazine.load_sequence(resolved)
	if bag.is_empty():
		needs_reshuffle_next_load = true
	_fire_queue = magazine.fire_order()
	_fire_damages = FireResolver.compute_shot_damages(_fire_queue, pink_bonus)
	_fire_index = 0
	_set_phase(Phase.FIRING)
	while _fire_index < _fire_queue.size():
		if alive_enemies().is_empty():
			break
		var hammer: int = magazine.chamber_at_fire_port()
		if magazine.slots[hammer] == Magazine.EMPTY:
			_advance_cylinder_one_step()
			if magazine.is_empty():
				break
			continue
		var ammo_id: int = _fire_queue[_fire_index]
		var base_dmg: int = _fire_damages[_fire_index]
		_consume_hammer_chamber(ammo_id)
		var flags := FireResolver.inherits_from(ammo_id)
		var pierce := _muzzle_pierce or bool(flags["pierce"])
		var gas := _muzzle_gas or bool(flags["gas"])
		var fire := _muzzle_fire or bool(flags["fire"])
		var water := _muzzle_water or bool(flags["water"])
		var thunder := _muzzle_thunder or bool(flags["thunder"])
		_fire_total_damage += _apply_shot_to_enemies(ammo_id, base_dmg, pierce, gas, fire, water, thunder)
		discard.append(ammo_id)
		_mount_muzzle_from(flags)
		_fire_index += 1
		_remove_dead()
	# 额外轮未打完的弹归袋（中途清场时）
	if not magazine.is_empty():
		_return_magazine_to_bag()
	else:
		magazine.clear()
	_log("金色额外轮射击完毕。")
	# 恢复主匣未击发弹药与射击队列进度
	magazine.slots = saved_slots
	magazine.start_index = saved_start
	_fire_queue = saved_queue
	_fire_damages = saved_damages
	_fire_index = saved_index
	last_shot_was_blank = false
	last_fired_slot = -1
	return true


func do_fire() -> bool:
	if not begin_fire():
		return false
	while phase == Phase.FIRING:
		fire_next_shot()
	return true


## 仅转动转轮并记日志；不结束行动（供装填后 spin / UI 动画先转再结算）。失败 -1；多发步数 ∈ [1,size-1]，单发 0。
func apply_roll() -> int:
	if not can_start_roll():
		return -1
	var before := magazine.start_index
	var steps: int = magazine.random_roll(rng)
	if magazine.loaded_count() <= 1:
		_log("重 roll：仅 %d 发，转轮不转（步数 0）。" % magazine.loaded_count())
	else:
		_log("重 roll：大盘随机转动 %d 步（击发红圈固定）。起点槽 %d → %d。" % [
			steps, before, magazine.start_index
		])
	_emit()
	return steps


## 玩家行动（射击/卸除/ROLL）结束后：判胜负或进入怪物回合。
func resolve_after_player_action() -> void:
	if _check_end_after_player():
		_emit()
		return
	_run_enemy_turn()
	_emit()


## 随机转轮并结束本回合（进怪物回合）。匣内仍有弹则怪回合后回 AWAIT_ACTION。UI：先 apply_roll 再 resolve_after_player_action。
func begin_roll() -> bool:
	if apply_roll() < 0:
		return false
	resolve_after_player_action()
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
		_enter_won()
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
			var dealt: int = e.apply_damage(b)
			e.burn_stacks = maxi(0, e.burn_stacks - 1)
			_log("%s 燃烧结算伤害%d，燃烧剩余%d" % [e.name_zh, dealt, e.burn_stacks])
	_remove_dead()
	if alive_enemies().is_empty():
		_enter_won()
		return
	var order: Array = enemies_sorted_by_cell()
	for e in order:
		_move_enemy(e)
		if can_attack_player(e):
			player_hp = maxi(0, player_hp - e.atk)
			if e.atk > 0:
				wave_took_damage = true
			_log("%s 攻击玩家，造成 %d（玩家 HP %d/%d · 射程 %d）" % [
				e.name_zh, e.atk, player_hp, player_max_hp, e.attack_range
			])
		else:
			_log("%s 未进入射程，不攻击（格 %d · 射程 %d）。" % [e.name_zh, e.cell, e.attack_range])
	if player_hp <= 0:
		_lose_hp()
		return
	_tick_bleed_end_of_enemy_turn()
	_remove_dead()
	if alive_enemies().is_empty():
		_enter_won()
		return
	# Boss 独特效果：每怪物回合向袋塞无效弹（灰盒暂定）
	if encounter_kind == EncounterKind.BOSS:
		_inject_invalid_ammo(CombatConstants.BOSS_INVALID_PER_ENEMY_TURN, "回合末")
	# ROLL 不清空弹匣：匣内仍有弹 → 可继续 FIRE/ROLL/UNLOAD；仅空匣才要求装填
	if magazine.is_empty():
		_set_phase(Phase.AWAIT_LOAD)
		_log("--- 请装填 ---")
	else:
		_set_phase(Phase.AWAIT_ACTION)
		_log("--- 请选择行动（膛内仍有弹药）---")


func _tick_bleed_end_of_enemy_turn() -> void:
	## 生物流血：回合结束失去等同层数生命，然后层数-1。石头对 debuff 伤害同样无视 <4。
	for e in alive_enemies():
		if e.bleed_stacks <= 0:
			continue
		var stacks: int = e.bleed_stacks
		var dealt: int = e.apply_damage(stacks)
		e.bleed_stacks = maxi(0, e.bleed_stacks - 1)
		_log("%s 流血结算伤害%d（层%d→%d）" % [e.name_zh, dealt, stacks, e.bleed_stacks])


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



func _clear_reward_state() -> void:
	reward_pending = false
	reward_resolved = false
	reward_choices.clear()


## 进入胜利：发基础金币并生成三选一；无伤/三回合额外金灰盒预留钩子暂不结算。
func _enter_won() -> void:
	if phase == Phase.WON and (reward_pending or reward_resolved):
		return
	_set_phase(Phase.WON)
	_log("胜利：敌人全灭。")
	# 练习战：胜利后先把弹仓/弃牌/袋重置为开局练习牌库，再发奖励（选弹叠在初始袋上）
	if not from_map_run:
		_reset_practice_ammo_to_starter()
	_begin_reward()


func _reset_practice_ammo_to_starter() -> void:
	## 练习战专用：匣清空、弃牌清空、袋恢复 STARTER_WHITE_COUNT 发白弹。
	magazine = Magazine.new()
	discard.clear()
	bag.clear()
	for _i in CombatConstants.STARTER_WHITE_COUNT:
		bag.append(CombatConstants.WHITE_AMMO_ID)
	_shuffle(bag)
	needs_reshuffle_next_load = false
	last_load_ids.clear()
	_reset_fire_session()
	_reset_muzzle()
	_pending_gold_autofires = 0
	_reset_load_session()
	_log("练习战：弹药已重置为开局牌库（白弹 ×%d）。" % CombatConstants.STARTER_WHITE_COUNT)


func _begin_reward() -> void:
	reward_choices = generate_reward_choices()
	reward_pending = true
	reward_resolved = false
	var base_g: int = reward_base_gold_for_encounter()
	last_reward_base_gold = base_g
	gold += base_g
	_log("奖励（%s）：基础金币 +%d（现 %d）。请三选一弹药，或放弃换额外金币。" % [
		encounter_label(), base_g, gold
	])
	# 灰盒预留钩子（数值为 0 / 未启用）：
	# var no_dmg := _hook_no_damage_bonus_gold()
	# var fast := _hook_fast_clear_bonus_gold()
	_emit()


## 从启用弹药表随机抽 3 个（池≥3 时去重；不足则允许重复）。同名可多份入袋。
func generate_reward_choices() -> Array[int]:
	var pool: Array[int] = []
	for item in DataRegistry.all_ammo():
		if bool(item.get("enabled_in_combat", false)):
			pool.append(int(item["id"]))
	if pool.is_empty():
		pool.append(CombatConstants.WHITE_AMMO_ID)
	var out: Array[int] = []
	var need: int = CombatConstants.REWARD_CHOICE_COUNT
	if pool.size() >= need:
		var work: Array[int] = pool.duplicate()
		_shuffle(work)
		for i in need:
			out.append(work[i])
	else:
		for _i in need:
			out.append(pool[rng.randi_range(0, pool.size() - 1)])
	return out


func can_pick_reward() -> bool:
	return phase == Phase.WON and reward_pending and not reward_resolved


## 选择三选一中的第 index 发（0..2），加入弹药袋。
func pick_reward_ammo(index: int) -> bool:
	if not can_pick_reward():
		return false
	if index < 0 or index >= reward_choices.size():
		return false
	var ammo_id: int = reward_choices[index]
	bag.append(ammo_id)
	reward_pending = false
	reward_resolved = true
	_log("奖励：选择 %s 加入弹药袋（袋内 %d）。" % [_ammo_name(ammo_id), bag.size()])
	_emit()
	return true


## 放弃三选一，换额外金币。
func skip_reward_for_gold() -> bool:
	if not can_pick_reward():
		return false
	var extra: int = CombatConstants.REWARD_SKIP_EXTRA_GOLD
	gold += extra
	reward_pending = false
	reward_resolved = true
	_log("奖励：放弃三选一，额外金币 +%d（现 %d）。" % [extra, gold])
	_emit()
	return true


## 灰盒预留：无伤通关额外金（当前恒 0）。
func _hook_no_damage_bonus_gold() -> int:
	if wave_took_damage:
		return 0
	return CombatConstants.REWARD_NO_DAMAGE_EXTRA_GOLD


## 灰盒预留：三回合内通关额外金（当前恒 0）。
func _hook_fast_clear_bonus_gold() -> int:
	if wave_player_turns > CombatConstants.REWARD_FAST_CLEAR_TURN_LIMIT:
		return 0
	return CombatConstants.REWARD_FAST_CLEAR_EXTRA_GOLD


func can_start_next_wave() -> bool:
	## 奖励结算完成后才可下一波（不重置弹药袋）。
	return phase == Phase.WON and reward_resolved and not reward_pending


## 清场后开始下一波：随机/轮换现有启用敌人，不回主菜单、不重置弹药袋。
func start_next_wave() -> bool:
	if not can_start_next_wave():
		return false
	wave_index += 1
	enemies.clear()
	_spawn_wave_enemies()
	lose_reason = LoseReason.NONE
	_reset_fire_session()
	_reset_muzzle()
	_pending_gold_autofires = 0
	_reset_load_session()
	_clear_reward_state()
	wave_took_damage = false
	wave_player_turns = 0
	_set_phase(Phase.AWAIT_LOAD)
	_log("—— 第 %d 波开始：敌人已刷新，请装填。——" % wave_index)
	_emit()
	return true


func _spawn_wave_enemies(force_ids: Array = []) -> void:
	var ids: Array[int] = []
	if force_ids.size() > 0:
		for x in force_ids:
			ids.append(int(x))
	elif encounter_kind == EncounterKind.BOSS:
		ids.append(CombatConstants.BOSS_BODY_ENEMY_ID)
	else:
		var pool: Array[int] = []
		for item in DataRegistry.all_enemies():
			if bool(item.get("enabled_in_combat", false)):
				pool.append(int(item["id"]))
		if pool.is_empty():
			pool.append(CombatConstants.CIVILIAN_ENEMY_ID)
		var count: int
		if encounter_kind == EncounterKind.ELITE:
			count = CombatConstants.ELITE_ENEMY_COUNT
		else:
			# 第 n 波：1/2/3 循环数量
			count = 1 + ((wave_index - 1) % 3)
		for _i in count:
			ids.append(pool[rng.randi_range(0, pool.size() - 1)])
	var cell: int = CombatConstants.BOARD_SIZE - 1
	for eid in ids:
		if cell <= CombatConstants.PLAYER_CELL:
			break
		while occupied_cells().has(cell) and cell > CombatConstants.PLAYER_CELL + 1:
			cell -= 1
		if occupied_cells().has(cell) or cell <= CombatConstants.PLAYER_CELL:
			break
		var def: Dictionary = DataRegistry.get_enemy(eid)
		if def.is_empty():
			continue
		var e: EnemyInstance = _make_scaled_enemy(def, cell)
		enemies.append(e)
		_log("波次 %d：%s 出现在格 %d（HP%d 攻%d 移%d 射程%d）。" % [
			wave_index, e.name_zh, cell, e.max_hp, e.atk, e.mobility, e.attack_range
		])
		cell -= 1


func _parse_encounter(s: String) -> int:
	match s:
		"elite":
			return EncounterKind.ELITE
		"boss":
			return EncounterKind.BOSS
		_:
			return EncounterKind.NORMAL


func encounter_label() -> String:
	match encounter_kind:
		EncounterKind.ELITE:
			return "精英战"
		EncounterKind.BOSS:
			return "Boss 终战"
		_:
			return "战斗"


func reward_base_gold_for_encounter() -> int:
	match encounter_kind:
		EncounterKind.ELITE:
			return CombatConstants.REWARD_ELITE_BASE_GOLD
		EncounterKind.BOSS:
			return CombatConstants.REWARD_BOSS_BASE_GOLD
		_:
			return CombatConstants.REWARD_BASE_GOLD


## 按遭遇类型缩放现有敌人（不新增敌人表行）。
func _make_scaled_enemy(def: Dictionary, cell: int) -> EnemyInstance:
	var e := EnemyInstance.new(def, cell)
	match encounter_kind:
		EncounterKind.ELITE:
			e.max_hp = maxi(1, int(round(float(e.max_hp) * CombatConstants.ELITE_HP_MULT)))
			e.hp = e.max_hp
			e.atk = maxi(0, int(round(float(e.atk) * CombatConstants.ELITE_ATK_MULT)))
			e.mobility += CombatConstants.ELITE_MOBILITY_BONUS
			e.attack_range = CombatConstants.ELITE_ATTACK_RANGE
			e.name_zh = "精英·" + e.name_zh
		EncounterKind.BOSS:
			e.max_hp = maxi(1, int(round(float(e.max_hp) * CombatConstants.BOSS_HP_MULT)))
			e.hp = e.max_hp
			e.atk = maxi(0, int(round(float(e.atk) * CombatConstants.BOSS_ATK_MULT)))
			e.mobility += CombatConstants.BOSS_MOBILITY_BONUS
			e.attack_range = CombatConstants.BOSS_ATTACK_RANGE
			e.name_zh = "Boss·" + e.name_zh
		_:
			pass
	return e


## Boss 向弹药袋塞入无效弹药（本地常量 id，非 Excel）。
func _inject_invalid_ammo(count: int, reason: String = "") -> void:
	if count <= 0:
		return
	for _i in count:
		bag.append(CombatConstants.INVALID_AMMO_ID)
	var tag: String = reason if reason != "" else "效果"
	_log("Boss[%s]：弹药袋 +无效弹药 ×%d（袋内 %d）。击发伤害 0。" % [tag, count, bag.size()])


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
		_enter_won()
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
