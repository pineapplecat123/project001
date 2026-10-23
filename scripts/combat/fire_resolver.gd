class_name FireResolver
## 整匣射击：按表计算每发基础伤害与黑/蓝全局修正。

const YELLOW_TABLE := [0, 1, 2, 3, 4, 5, 5]
const PURPLE_TABLE := [0, 0, 3, 4, 5, 5, 5]
const RED_BONUS := {1: 1, 2: 3, 3: 5, 4: 6, 5: 7}

const ID_WHITE := 1
const ID_BLACK := 2
const ID_GREEN := 3
const ID_YELLOW := 4
const ID_PURPLE := 5
const ID_RED := 6
const ID_BLUE := 7
const ID_GOLD := 8
const ID_PINK := 9
const ID_BW := 10
const ID_PIERCE := 11
const ID_GAS := 12
const ID_FIRE := 13
const ID_WATER := 14
const ID_THUNDER := 15


static func count_by_id(order: Array[int]) -> Dictionary:
	var c := {}
	for id in order:
		c[id] = int(c.get(id, 0)) + 1
	return c


static func unique_count(order: Array[int]) -> int:
	var s := {}
	for id in order:
		s[id] = true
	return s.size()


static func purple_run_lengths(order: Array[int]) -> Array[int]:
	var n := order.size()
	var out: Array[int] = []
	out.resize(n)
	var i := 0
	while i < n:
		if order[i] != ID_PURPLE:
			out[i] = 0
			i += 1
			continue
		var j := i
		while j < n and order[j] == ID_PURPLE:
			j += 1
		var run_len := j - i
		for k in range(i, j):
			out[k] = run_len
		i = j
	return out


static func green_multipliers(order: Array[int]) -> Array[int]:
	var n := order.size()
	var out: Array[int] = []
	out.resize(n)
	for i in n:
		out[i] = 1
	if n == 0:
		return out
	var all_green := true
	for id in order:
		if id != ID_GREEN:
			all_green = false
			break
	if all_green:
		for i in n:
			out[i] = 0
		return out
	var end := n - 1
	while end >= 0 and order[end] == ID_GREEN:
		end -= 1
	var dist := 1
	for i in range(n - 1, end, -1):
		out[i] = dist + 1
		dist += 1
	return out


static func base_damage_for(ammo_id: int, order: Array[int], index: int, pink_bonus: int) -> int:
	var counts := count_by_id(order)
	var yellow_n: int = int(counts.get(ID_YELLOW, 0))
	match ammo_id:
		ID_WHITE:
			return 3
		ID_BLACK:
			return 0
		ID_GREEN:
			return 2 * int(green_multipliers(order)[index])
		ID_YELLOW:
			return YELLOW_TABLE[clampi(yellow_n, 0, 6)]
		ID_PURPLE:
			var rl: int = clampi(int(purple_run_lengths(order)[index]), 0, 6)
			return PURPLE_TABLE[rl]
		ID_RED:
			return 3 + int(RED_BONUS.get(yellow_n, 0))
		ID_BLUE:
			return 1 + unique_count(order)
		ID_GOLD:
			return 0
		ID_PINK:
			return 3 + pink_bonus
		ID_BW:
			return 0
		ID_PIERCE, ID_FIRE, ID_THUNDER:
			return 3
		ID_GAS:
			return 1
		ID_WATER:
			return 2
		_:
			return 0


static func black_triggers(order: Array[int]) -> bool:
	var counts := count_by_id(order)
	var black_n: int = int(counts.get(ID_BLACK, 0))
	if black_n <= 0:
		return false
	for id in counts.keys():
		if int(id) == ID_BLACK:
			continue
		if int(counts[id]) >= black_n:
			return false
	return true


static func blue_doubles_all(order: Array[int]) -> bool:
	return order.has(ID_BLUE) and unique_count(order) >= 6


static func compute_shot_damages(order: Array[int], pink_bonus: int) -> Array[int]:
	var out: Array[int] = []
	var black_x3 := black_triggers(order)
	var blue_x2 := blue_doubles_all(order)
	for i in order.size():
		var d: int = base_damage_for(order[i], order, i, pink_bonus)
		if black_x3:
			d *= 3
		if blue_x2:
			d *= 2
		out.append(d)
	return out


static func inherits_from(ammo_id: int) -> Dictionary:
	## 该发自带的状态效果旗标（击发后挂上枪口，本回合后续击发都附带）。
	return {
		"pierce": ammo_id == ID_PIERCE,
		"gas": ammo_id == ID_GAS,
		"fire": ammo_id == ID_FIRE,
		"water": ammo_id == ID_WATER,
		"thunder": ammo_id == ID_THUNDER,
	}


static func most_common_ids(ids: Array[int], rng: RandomNumberGenerator) -> int:
	## 返回数量最多的弹药 id；并列则随机。空则 -1。
	if ids.is_empty():
		return -1
	var counts := count_by_id(ids)
	var best := 0
	for id in counts.keys():
		best = maxi(best, int(counts[id]))
	var cands: Array[int] = []
	for id in counts.keys():
		if int(counts[id]) == best:
			cands.append(int(id))
	return cands[rng.randi_range(0, cands.size() - 1)]
