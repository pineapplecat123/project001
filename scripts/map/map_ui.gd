extends Control

const MapGraph = preload("res://scripts/map/map_graph.gd")
## 灰盒缩小版地图：选可达节点 → 战斗 / 占位路过 → 回地图。

const VERSION := "0.2.5"
const NODE_W := 120.0
const NODE_H := 72.0
const LAYER_GAP_X := 180.0
const SLOT_GAP_Y := 100.0
const ORIGIN := Vector2(80, 200)

const COL_GOLD := Color(1.0, 0.84, 0.3)
const COL_HP := Color(0.45, 0.95, 0.55)
const COL_BAG := Color(0.55, 0.85, 1.0)

var _node_buttons: Dictionary = {}  # id -> Button
var _bag_open: bool = false
var _toast_tween: Tween

@onready var status_label: Label = %StatusLabel
@onready var hp_label: Label = %HpLabel
@onready var gold_label: Label = %GoldLabel
@onready var bag_count_label: Label = %BagCountLabel
@onready var hint_label: Label = %HintLabel
@onready var toast_label: Label = %ToastLabel
@onready var graph_area: Control = %GraphArea
@onready var line_layer: Control = %LineLayer
@onready var node_layer: Control = %NodeLayer
@onready var btn_bag: Button = %BtnBag
@onready var btn_menu: Button = %BtnMenu
@onready var bag_panel: PanelContainer = %BagPanel
@onready var bag_list: VBoxContainer = %BagList
@onready var btn_bag_close: Button = %BtnBagClose
@onready var dimmer: ColorRect = %Dimmer
@onready var version_label: Label = %VersionLabel


func _ready() -> void:
	version_label.text = "v%s" % VERSION
	btn_bag.pressed.connect(_toggle_bag)
	btn_bag_close.pressed.connect(func(): _set_bag_open(false))
	btn_menu.pressed.connect(_on_menu)
	dimmer.gui_input.connect(_on_dimmer)
	bag_panel.visible = false
	dimmer.visible = false
	toast_label.visible = false
	if not RunState.active:
		RunState.begin_run()
	_rebuild_graph_ui()
	_refresh_header()
	if RunState.last_message != "":
		_show_toast(RunState.last_message)
		if RunState.run_finished:
			hint_label.text = "本局已结束。可返回主菜单重新开始。"


func _on_menu() -> void:
	RunState.end_run()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_dimmer(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_bag_open(false)


func _toggle_bag() -> void:
	_set_bag_open(not _bag_open)


func _set_bag_open(open: bool) -> void:
	_bag_open = open
	bag_panel.visible = open
	dimmer.visible = open
	if open:
		_refresh_bag_list()


func _refresh_header() -> void:
	hp_label.text = "HP %d / %d" % [RunState.player_hp, RunState.player_max_hp]
	hp_label.add_theme_color_override("font_color", COL_HP)
	gold_label.text = "金币 %d" % RunState.gold
	gold_label.add_theme_color_override("font_color", COL_GOLD)
	bag_count_label.text = "袋 %d" % RunState.bag.size()
	bag_count_label.add_theme_color_override("font_color", COL_BAG)
	if RunState.run_finished:
		status_label.text = "地图 · 本局结束"
	else:
		status_label.text = "地图 · 选择下一节点（当前：%s）" % _node_title(RunState.current_node_id)
	if not RunState.run_finished:
		hint_label.text = "高亮节点可点击。战斗进入现有战斗；商店/休息/事件为灰盒占位（路过无奖励）。地图上只能检视弹药袋。"


func _node_title(node_id: int) -> String:
	var n: Dictionary = MapGraph.node_by_id(RunState.graph, node_id)
	if n.is_empty():
		return "#%d" % node_id
	return "%s#%d" % [str(n.get("label", "?")), node_id]


func _rebuild_graph_ui() -> void:
	for c in node_layer.get_children():
		c.queue_free()
	for c in line_layer.get_children():
		c.queue_free()
	_node_buttons.clear()
	var positions: Dictionary = {}
	for n in RunState.graph.get("nodes", []):
		var id: int = int(n["id"])
		var layer: int = int(n.get("layer", 0))
		var slot: int = int(n.get("slot", 0))
		# layer1 有两个 slot：slot0 偏上、slot1 偏下
		var y_off: float = 0.0
		if int(n.get("type", 0)) != MapGraph.NodeType.START:
			var slots_in_layer := _slots_in_layer(layer)
			if slots_in_layer > 1:
				y_off = (float(slot) - (slots_in_layer - 1) * 0.5) * SLOT_GAP_Y
		var pos := ORIGIN + Vector2(layer * LAYER_GAP_X, y_off)
		positions[id] = pos
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(NODE_W, NODE_H)
		btn.position = pos
		btn.text = _button_text(n)
		btn.add_theme_font_size_override("font_size", 16)
		var nid := id
		btn.pressed.connect(func(): _on_node_pressed(nid))
		node_layer.add_child(btn)
		_node_buttons[id] = btn
	# 连线（用 ColorRect 近似线段）
	for e in RunState.graph.get("edges", []):
		var a: int = int(e[0])
		var b: int = int(e[1])
		if not positions.has(a) or not positions.has(b):
			continue
		_draw_edge(positions[a], positions[b])
	_refresh_node_states()


func _slots_in_layer(layer: int) -> int:
	var count := 0
	for n in RunState.graph.get("nodes", []):
		if int(n.get("layer", -1)) == layer:
			count += 1
	return maxi(count, 1)


func _button_text(n: Dictionary) -> String:
	var t: int = int(n.get("type", 0))
	var label: String = str(n.get("label", "?"))
	match t:
		MapGraph.NodeType.START:
			return "起点"
		MapGraph.NodeType.PLACEHOLDER:
			return "%s\n(占位)" % label
		MapGraph.NodeType.FINALE:
			return "终战"
		_:
			return "战斗"


func _draw_edge(from_pos: Vector2, to_pos: Vector2) -> void:
	var a := from_pos + Vector2(NODE_W, NODE_H * 0.5)
	var b := to_pos + Vector2(0, NODE_H * 0.5)
	var mid := (a + b) * 0.5
	var delta := b - a
	var len := delta.length()
	var line := ColorRect.new()
	line.color = Color(0.45, 0.5, 0.6, 0.7)
	line.size = Vector2(len, 3)
	line.pivot_offset = Vector2(0, 1.5)
	line.position = a - Vector2(0, 1.5)
	line.rotation = delta.angle()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_layer.add_child(line)
	# mid unused; keep for future arrow
	mid = mid


func _refresh_node_states() -> void:
	var avail: Array[int] = RunState.available_node_ids()
	for id in _node_buttons.keys():
		var btn: Button = _node_buttons[id]
		var n: Dictionary = MapGraph.node_by_id(RunState.graph, id)
		var done: bool = RunState.is_completed(id)
		var can: bool = avail.has(id) and not RunState.run_finished
		btn.disabled = not can
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		if done:
			style.bg_color = Color(0.22, 0.28, 0.22)
			style.border_color = Color(0.4, 0.55, 0.4)
			btn.modulate = Color(0.75, 0.75, 0.75)
		elif can:
			style.bg_color = Color(0.2, 0.35, 0.55)
			style.border_color = Color(1.0, 0.85, 0.25)
			style.set_border_width_all(3)
			btn.modulate = Color(1, 1, 1)
		else:
			style.bg_color = Color(0.18, 0.18, 0.22)
			style.border_color = Color(0.35, 0.35, 0.4)
			btn.modulate = Color(0.55, 0.55, 0.6)
		# 当前所在
		if id == RunState.current_node_id:
			style.border_color = Color(0.4, 0.9, 1.0)
			style.set_border_width_all(3)
		var t: int = int(n.get("type", 0))
		if t == MapGraph.NodeType.PLACEHOLDER and can:
			style.bg_color = Color(0.35, 0.28, 0.18)
		if t == MapGraph.NodeType.FINALE and can:
			style.bg_color = Color(0.45, 0.18, 0.22)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("disabled", style)
		btn.add_theme_stylebox_override("pressed", style)


func _on_node_pressed(node_id: int) -> void:
	if RunState.run_finished:
		_show_toast("本局已结束，请返回主菜单。")
		return
	if not RunState.available_node_ids().has(node_id):
		return
	var n: Dictionary = MapGraph.node_by_id(RunState.graph, node_id)
	var t: int = int(n.get("type", -1))
	match t:
		MapGraph.NodeType.COMBAT, MapGraph.NodeType.FINALE:
			if RunState.enter_combat_node(node_id):
				get_tree().change_scene_to_file("res://scenes/combat.tscn")
		MapGraph.NodeType.PLACEHOLDER:
			var msg := RunState.visit_placeholder(node_id)
			_show_toast(msg)
			_refresh_header()
			_refresh_node_states()
		_:
			_show_toast("无法进入该节点")


func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)
	_toast_tween.tween_callback(func(): toast_label.visible = false)


func _refresh_bag_list() -> void:
	for c in bag_list.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "弹药袋（只读 · 地图上不可变更构筑）· 共 %d 发 · 金币 %d" % [
		RunState.bag.size(), RunState.gold
	]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bag_list.add_child(title)
	if RunState.bag.is_empty():
		var empty := Label.new()
		empty.text = "（空）"
		bag_list.add_child(empty)
		return
	var counts: Dictionary = {}
	for ammo_id in RunState.bag:
		counts[ammo_id] = int(counts.get(ammo_id, 0)) + 1
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var ids: Array = counts.keys()
	ids.sort()
	for ammo_id in ids:
		var def: Dictionary = DataRegistry.get_ammo(int(ammo_id))
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(140, 72)
		var vb := VBoxContainer.new()
		var name_l := Label.new()
		var short := str(def.get("name", ammo_id)).replace("弹药", "")
		name_l.text = short
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var cnt := Label.new()
		cnt.text = "×%d" % int(counts[ammo_id])
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(name_l)
		vb.add_child(cnt)
		cell.add_child(vb)
		grid.add_child(cell)
	bag_list.add_child(grid)
	var tip := Label.new()
	tip.text = "抽弹纯随机，网格不代表顺序。"
	tip.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
	bag_list.add_child(tip)
