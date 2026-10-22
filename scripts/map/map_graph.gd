class_name MapGraph
## 灰盒缩小版地图：短分叉 + 合流，战斗/精英/终战 + 1 个非战斗占位。
## 拓扑固定；占位类型（商店/休息/事件）按种子随机三选一。
## 商店、休息已实现灰盒 UI；特殊事件仍占位路过（待用户交事件表）。
## 精英=现有敌人数值提升；终战=Boss（更高数值+塞无效弹）；均不新造敌人表行。

enum NodeType {
	START = 0,
	COMBAT = 1,
	PLACEHOLDER = 2,
	FINALE = 3,
	ELITE = 4,
}

const PLACEHOLDER_KINDS: Array[String] = ["商店", "休息", "特殊事件"]
const KIND_SHOP := "商店"
const KIND_REST := "休息"


## 生成迷你图。返回 { nodes: Array[Dictionary], edges: Array[Array] }。
## 节点字段：id, type, label, layer, slot, kind(可选)
## force_kind 非空且合法时固定占位种类（测试用）。
static func build_mini(seed_value: int = 0, force_kind: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var kind: String
	if force_kind != "" and PLACEHOLDER_KINDS.has(force_kind):
		kind = force_kind
	else:
		kind = PLACEHOLDER_KINDS[rng.randi_range(0, PLACEHOLDER_KINDS.size() - 1)]
	var nodes: Array = [
		{"id": 0, "type": NodeType.START, "label": "起点", "layer": 0, "slot": 0},
		{"id": 1, "type": NodeType.COMBAT, "label": "战斗", "layer": 1, "slot": 0},
		{"id": 2, "type": NodeType.COMBAT, "label": "战斗", "layer": 1, "slot": 1},
		{"id": 3, "type": NodeType.PLACEHOLDER, "label": kind, "layer": 2, "slot": 0, "kind": kind},
		{"id": 4, "type": NodeType.ELITE, "label": "精英", "layer": 3, "slot": 0},
		{"id": 5, "type": NodeType.FINALE, "label": "终战", "layer": 4, "slot": 0},
	]
	var edges: Array = [
		[0, 1], [0, 2],
		[1, 3], [2, 3],
		[3, 4],
		[4, 5],
	]
	return {"nodes": nodes, "edges": edges}


static func node_by_id(graph: Dictionary, node_id: int) -> Dictionary:
	for n in graph.get("nodes", []):
		if int(n.get("id", -1)) == node_id:
			return n
	return {}


static func neighbors(graph: Dictionary, from_id: int) -> Array[int]:
	var out: Array[int] = []
	for e in graph.get("edges", []):
		if int(e[0]) == from_id:
			out.append(int(e[1]))
	return out


static func is_shop_node(n: Dictionary) -> bool:
	if n.is_empty():
		return false
	if int(n.get("type", -1)) != NodeType.PLACEHOLDER:
		return false
	return str(n.get("kind", "")) == KIND_SHOP


static func is_rest_node(n: Dictionary) -> bool:
	if n.is_empty():
		return false
	if int(n.get("type", -1)) != NodeType.PLACEHOLDER:
		return false
	return str(n.get("kind", "")) == KIND_REST


static func is_elite_node(n: Dictionary) -> bool:
	return not n.is_empty() and int(n.get("type", -1)) == NodeType.ELITE


static func is_boss_node(n: Dictionary) -> bool:
	return not n.is_empty() and int(n.get("type", -1)) == NodeType.FINALE


static func is_combat_like(n: Dictionary) -> bool:
	if n.is_empty():
		return false
	var t: int = int(n.get("type", -1))
	return t == NodeType.COMBAT or t == NodeType.ELITE or t == NodeType.FINALE


static func type_name(t: int) -> String:
	match t:
		NodeType.START:
			return "起点"
		NodeType.COMBAT:
			return "战斗"
		NodeType.PLACEHOLDER:
			return "非战斗"
		NodeType.FINALE:
			return "终战"
		NodeType.ELITE:
			return "精英"
		_:
			return "未知"
