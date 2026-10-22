class_name Magazine
## 弹夹：长度固定的有序结算队列；空槽用 -1。

const EMPTY := -1

var slots: Array[int] = []
var start_index: int = 0


func _init(size: int = CombatConstants.MAGAZINE_SIZE) -> void:
	slots.clear()
	for _i in size:
		slots.append(EMPTY)
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
	start_index = 0


## 按顺序填入 ammo_ids（从槽 0 起）；返回实际装入数量。
func load_sequence(ammo_ids: Array[int]) -> int:
	clear()
	var n: int = mini(ammo_ids.size(), slots.size())
	for i in n:
		slots[i] = ammo_ids[i]
	start_index = 0
	return n


## 将 start_index 设为 new_start（须为已装填槽）。不改变相对顺序。
func set_start(new_start: int) -> void:
	assert(new_start >= 0 and new_start < slots.size())
	assert(slots[new_start] != EMPTY)
	start_index = new_start


## 顺时针把起点挪一格到下一个已装填槽；若只剩 0/1 发则不变。
func rotate_start_forward() -> void:
	if loaded_count() <= 1:
		return
	var i := (start_index + 1) % slots.size()
	while slots[i] == EMPTY:
		i = (i + 1) % slots.size()
		if i == start_index:
			return
	start_index = i


## 自起点起、跳过空槽，返回击发顺序中的弹药 id 列表。
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


## 卸除：返回所有非空弹药 id（任意顺序稳定：从 0 到末），并清空。
func unload_all() -> Array[int]:
	var out: Array[int] = []
	for id in slots:
		if id != EMPTY:
			out.append(id)
	clear()
	return out
