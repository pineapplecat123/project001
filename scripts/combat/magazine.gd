class_name Magazine
## 弹夹：左轮环形结算队列；空槽用 -1。
## start_index = 当前对准固定击发点（锤位）的槽；相对顺序不变，ROLL 只转 start_index。

const EMPTY := -1

var slots: Array[int] = []
## 与 slots 平行：该仓是否为战斗内临时额外罪孽（半透明）
var temp_slots: Array[bool] = []
var start_index: int = 0


func _init(size: int = CombatConstants.MAGAZINE_SIZE) -> void:
	slots.clear()
	temp_slots.clear()
	for _i in size:
		slots.append(EMPTY)
		temp_slots.append(false)
	start_index = 0


func size() -> int:
	return slots.size()


func loaded_count() -> int:
	var n := 0
	for id in slots:
		if id != EMPTY:
			n += 1
	return n


func is_empty() -> bool:
	return loaded_count() == 0


func clear() -> void:
	for i in slots.size():
		slots[i] = EMPTY
		if i < temp_slots.size():
			temp_slots[i] = false
		else:
			temp_slots.append(false)
	start_index = 0


## 写入单个仓位（逐步装填用）。
func set_slot(index: int, ammo_id: int, temporary: bool = false) -> void:
	assert(index >= 0 and index < slots.size())
	slots[index] = ammo_id
	_ensure_temp_size()
	temp_slots[index] = temporary and ammo_id != EMPTY


## 按顺序填入 ammo_ids（从槽 0 起）；返回实际装入数量。
func load_sequence(ammo_ids: Array[int], temporary_flags: Array = []) -> int:
	clear()
	var n: int = mini(ammo_ids.size(), slots.size())
	for i in n:
		slots[i] = ammo_ids[i]
		var is_temp := false
		if i < temporary_flags.size():
			is_temp = bool(temporary_flags[i])
		temp_slots[i] = is_temp and ammo_ids[i] != EMPTY
	start_index = 0
	return n


## 将 start_index 设为 new_start。不改变相对顺序。
func set_start(new_start: int) -> void:
	assert(new_start >= 0 and new_start < slots.size())
	start_index = new_start


## 顺时针把起点挪一格（测试/调试用）。
func rotate_start_forward() -> void:
	if slots.is_empty():
		return
	start_index = (start_index + 1) % slots.size()


## 随机转动转轮：改变对准击发点的槽，相对顺序不变。
## 仅 0/1 发时步数为 0；否则步数 ∈ [1, size-1]（必转，避免视觉上不动）。
## 返回逻辑步数；UI 可再加整圈基数做「转一圈」动画。
func random_roll(p_rng: RandomNumberGenerator) -> int:
	if loaded_count() <= 1 or slots.size() <= 1:
		return 0
	var steps: int = p_rng.randi_range(1, slots.size() - 1)
	start_index = (start_index + steps) % slots.size()
	return steps


## 自击发点起顺时针、跳过空槽，返回击发顺序中的弹药 id 列表。
func fire_order() -> Array[int]:
	var out: Array[int] = []
	if is_empty():
		return out
	var seen := 0
	var i := start_index
	while seen < slots.size():
		if slots[i] != EMPTY:
			out.append(slots[i])
		i = (i + 1) % slots.size()
		seen += 1
	return out


## 卸除：返回所有非空弹药 id（从 0 到末），并清空。
func unload_all() -> Array[int]:
	var out: Array[int] = []
	for id in slots:
		if id != EMPTY:
			out.append(id)
	clear()
	return out


## 给定「正上击发仓」步数，返回处于击发点的仓位下标。
func chamber_at_fire_port(steps: int = -1) -> int:
	var s: int = start_index if steps < 0 else steps
	return posmod(s + CombatConstants.FIRE_PORT_OFFSET_STEPS, size())


## 给定「正上击发仓」步数，返回处于左上上弹口的仓位下标。
func chamber_at_load_port(steps: int = -1) -> int:
	var s: int = start_index if steps < 0 else steps
	return posmod(s + CombatConstants.LOAD_PORT_OFFSET_STEPS, size())


func _ensure_temp_size() -> void:
	while temp_slots.size() < slots.size():
		temp_slots.append(false)


func is_slot_temporary(index: int) -> bool:
	if index < 0 or index >= temp_slots.size():
		return false
	return bool(temp_slots[index]) and slots[index] != EMPTY


## 卸除：返回 [{id, temp}, ...]
func unload_all_entries() -> Array:
	var out: Array = []
	for i in slots.size():
		if slots[i] != EMPTY:
			out.append({"id": slots[i], "temp": is_slot_temporary(i)})
	clear()
	return out
