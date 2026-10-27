class_name ShopState
## 商店会话逻辑（纯数据）。打开时拷贝 gold/bag；离开时写回 RunState。
## 库存随机、无稀有度权重；购买入袋；移除费用单店递增，离店重置；罪孽弹药不可去除。

const ShopConstants = preload("res://scripts/shop/shop_constants.gd")

var open: bool = false
var node_id: int = -1
var gold: int = 0
var bag: Array[int] = []
## 货架上的弹药 id；与 sold 等长
var stock: Array[int] = []
var sold: Array[bool] = []
var removes_done: int = 0
var free_rerolls_left: int = ShopConstants.FREE_REROLLS
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var last_message: String = ""


func begin(from_gold: int, from_bag: Array, shop_node_id: int, seed_value: int = 0) -> void:
	open = true
	node_id = shop_node_id
	gold = from_gold
	bag = _copy_ints(from_bag)
	removes_done = 0
	free_rerolls_left = ShopConstants.FREE_REROLLS
	last_message = ""
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_roll_stock()


func end_session() -> Dictionary:
	## 离店：重置本店移除计数与免费重随（下次 begin 也会重置）。
	var payload := {
		"gold": gold,
		"bag": bag.duplicate(),
		"node_id": node_id,
	}
	open = false
	node_id = -1
	removes_done = 0
	free_rerolls_left = ShopConstants.FREE_REROLLS
	stock.clear()
	sold.clear()
	last_message = ""
	return payload


func ammo_price(_ammo_id: int = 0) -> int:
	## 灰盒暂定：全弹统一价，不读表。
	return ShopConstants.AMMO_PRICE


func next_remove_cost() -> int:
	return ShopConstants.REMOVE_BASE_COST + removes_done * ShopConstants.REMOVE_COST_STEP


func reroll_cost_now() -> int:
	if free_rerolls_left > 0:
		return 0
	return ShopConstants.REROLL_COST


func can_buy(slot: int) -> bool:
	if not open:
		return false
	if slot < 0 or slot >= stock.size():
		return false
	if sold[slot]:
		return false
	return gold >= ammo_price(stock[slot])


func buy(slot: int) -> bool:
	if not can_buy(slot):
		last_message = "无法购买（已售出或金币不足）。"
		return false
	var ammo_id: int = stock[slot]
	var price: int = ammo_price(ammo_id)
	gold -= price
	bag.append(ammo_id)
	sold[slot] = true
	last_message = "购买 %s，-%d 金。" % [_ammo_name(ammo_id), price]
	return true


func can_remove_at(bag_index: int) -> bool:
	if not open:
		return false
	if bag_index < 0 or bag_index >= bag.size():
		return false
	if DataRegistry.is_sin_ammo(int(bag[bag_index])):
		return false
	return gold >= next_remove_cost()


func remove_at(bag_index: int) -> bool:
	if bag_index >= 0 and bag_index < bag.size() and DataRegistry.is_sin_ammo(int(bag[bag_index])):
		last_message = "罪孽弹药不可去除。"
		return false
	if not can_remove_at(bag_index):
		last_message = "无法移除（索引无效或金币不足）。"
		return false
	var cost: int = next_remove_cost()
	var ammo_id: int = bag[bag_index]
	gold -= cost
	bag.remove_at(bag_index)
	removes_done += 1
	last_message = "移除 %s，-%d 金（本店第 %d 次）。" % [_ammo_name(ammo_id), cost, removes_done]
	return true


func can_reroll() -> bool:
	if not open:
		return false
	return gold >= reroll_cost_now()


func reroll() -> bool:
	if not can_reroll():
		last_message = "金币不足，无法重随。"
		return false
	var cost: int = reroll_cost_now()
	if free_rerolls_left > 0:
		free_rerolls_left -= 1
		last_message = "免费重随库存。"
	else:
		gold -= cost
		last_message = "重随库存，-%d 金。" % cost
	_roll_stock()
	return true


func _roll_stock() -> void:
	var pool: Array[int] = _enabled_ammo_ids()
	if pool.is_empty():
		pool.append(CombatConstants.WHITE_AMMO_ID)
	stock.clear()
	sold.clear()
	## 无稀有度权重：均匀随机；尽量不重复，池不够则允许重复。
	var work: Array[int] = pool.duplicate()
	_shuffle(work)
	for i in ShopConstants.STOCK_SIZE:
		if i < work.size():
			stock.append(work[i])
		else:
			stock.append(pool[rng.randi_range(0, pool.size() - 1)])
		sold.append(false)


func _enabled_ammo_ids() -> Array[int]:
	var out: Array[int] = []
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if DataRegistry.is_ammo_reward_eligible(aid):
			out.append(aid)
	return out


func _ammo_name(ammo_id: int) -> String:
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	return str(def.get("name", ammo_id))


func _shuffle(arr: Array[int]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _copy_ints(src) -> Array[int]:
	var out: Array[int] = []
	for x in src:
		out.append(int(x))
	return out
