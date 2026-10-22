extends Control
## 灰盒战斗 UI：棋盘 + 环形转轮 + LOAD/FIRE/ROLL/UNLOAD + 检视袋 + 开发者工具。
## FIRE：逐发 0.4s 间隔，射击中禁用行动按钮。

const CELL_W := 88
const CELL_H := 72
const WHEEL_SIZE := 240.0
const CHAMBER_SIZE := 58.0
const WHEEL_RADIUS := 78.0
const FIRE_SHOT_DELAY := 0.4

var state: CombatState
var _chamber_panels: Array[Panel] = []
var _bag_open: bool = false
var _dev_open: bool = false
var _firing: bool = false

@onready var phase_label: Label = %PhaseLabel
@onready var hp_label: Label = %HpLabel
@onready var bag_label: Label = %BagLabel
@onready var gold_label: Label = %GoldLabel
@onready var board_row: HBoxContainer = %BoardRow
@onready var mag_title: Label = %MagTitle
@onready var mag_wheel: Control = %MagWheel
@onready var fire_marker: Label = %FireMarker
@onready var log_box: RichTextLabel = %LogBox
@onready var btn_load: Button = %BtnLoad
@onready var btn_fire: Button = %BtnFire
@onready var btn_roll: Button = %BtnRoll
@onready var btn_unload: Button = %BtnUnload
@onready var btn_bag: Button = %BtnBag
@onready var btn_dev: Button = %BtnDev
@onready var btn_menu: Button = %BtnMenu
@onready var result_label: Label = %ResultLabel
@onready var bag_panel: PanelContainer = %BagPanel
@onready var bag_list: VBoxContainer = %BagList
@onready var btn_bag_close: Button = %BtnBagClose
@onready var dev_panel: PanelContainer = %DevPanel


func _ready() -> void:
	state = CombatState.new()
	state.phase_changed.connect(func(_p): _refresh())
	state.state_changed.connect(_refresh)
	state.log_line.connect(_on_log)
	btn_load.pressed.connect(_on_load)
	btn_fire.pressed.connect(_on_fire)
	btn_roll.pressed.connect(_on_roll)
	btn_unload.pressed.connect(_on_unload)
	btn_bag.pressed.connect(_toggle_bag)
	btn_dev.pressed.connect(_toggle_dev)
	btn_bag_close.pressed.connect(func(): _set_bag_open(false))
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	mag_title.text = "弹夹转轮（▼红标=固定击发点；数字=击发顺序顺时针；ROLL=随机转动）"
	_build_board_cells()
	_build_wheel_chambers()
	_wire_dev_buttons()
	bag_panel.visible = false
	dev_panel.visible = false
	state.start_graybox()
	_refresh()


func _on_log(text: String) -> void:
	log_box.append_text(text + "\n")


func _build_board_cells() -> void:
	for c in board_row.get_children():
		c.queue_free()
	for i in CombatConstants.BOARD_SIZE:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(CELL_W, CELL_H)
		panel.name = "Cell%d" % i
		var label := Label.new()
		label.name = "Info"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(label)
		board_row.add_child(panel)


func _build_wheel_chambers() -> void:
	_chamber_panels.clear()
	for c in mag_wheel.get_children():
		if c != fire_marker:
			c.queue_free()
	fire_marker.text = "▼击发"
	fire_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fire_marker.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	fire_marker.position = Vector2(WHEEL_SIZE * 0.5 - 30.0, 0.0)
	fire_marker.size = Vector2(60, 22)
	for i in CombatConstants.MAGAZINE_SIZE:
		var panel := Panel.new()
		panel.name = "Chamber%d" % i
		panel.custom_minimum_size = Vector2(CHAMBER_SIZE, CHAMBER_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.name = "Info"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(label)
		mag_wheel.add_child(panel)
		_chamber_panels.append(panel)
	_layout_wheel_chambers()


func _layout_wheel_chambers() -> void:
	var center := Vector2(WHEEL_SIZE * 0.5, WHEEL_SIZE * 0.5 + 8.0)
	var start_i: int = 0
	if state != null and state.magazine != null:
		start_i = state.magazine.start_index
	for slot_i in CombatConstants.MAGAZINE_SIZE:
		var order_k: int = (slot_i - start_i + CombatConstants.MAGAZINE_SIZE) % CombatConstants.MAGAZINE_SIZE
		var angle: float = -PI / 2.0 + float(order_k) * TAU / float(CombatConstants.MAGAZINE_SIZE)
		var pos := center + Vector2(cos(angle), sin(angle)) * WHEEL_RADIUS
		var panel: Panel = _chamber_panels[slot_i]
		panel.position = pos - Vector2(CHAMBER_SIZE, CHAMBER_SIZE) * 0.5
		panel.size = Vector2(CHAMBER_SIZE, CHAMBER_SIZE)


func _on_load() -> void:
	if _firing:
		return
	state.do_load()


func _on_fire() -> void:
	if _firing:
		return
	_run_fire_sequence()


func _run_fire_sequence() -> void:
	if not state.begin_fire():
		return
	_firing = true
	_refresh()
	while state.phase == CombatState.Phase.FIRING:
		var more: bool = state.fire_next_shot()
		_refresh()
		if more:
			await get_tree().create_timer(FIRE_SHOT_DELAY).timeout
		else:
			break
	_firing = false
	_refresh()


func _on_roll() -> void:
	if _firing:
		return
	state.begin_roll()


func _on_unload() -> void:
	if _firing:
		return
	state.do_unload()


func _toggle_bag() -> void:
	_set_bag_open(not _bag_open)


func _set_bag_open(open: bool) -> void:
	_bag_open = open
	bag_panel.visible = open
	if open:
		_dev_open = false
		dev_panel.visible = false
		_refresh_bag_list()


func _toggle_dev() -> void:
	_dev_open = not _dev_open
	dev_panel.visible = _dev_open
	if _dev_open:
		_bag_open = false
		bag_panel.visible = false


func _refresh_bag_list() -> void:
	for c in bag_list.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "弹药袋（只读 · 共 %d 发）｜弃牌 %d｜金币 %d" % [
		state.bag.size(), state.discard.size(), state.gold
	]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bag_list.add_child(title)
	if state.bag.is_empty():
		var empty := Label.new()
		empty.text = "（袋内为空）"
		bag_list.add_child(empty)
		return
	var counts: Dictionary = {}
	var order_ids: Array[int] = []
	for ammo_id in state.bag:
		if not counts.has(ammo_id):
			counts[ammo_id] = 0
			order_ids.append(ammo_id)
		counts[ammo_id] = int(counts[ammo_id]) + 1
	var idx := 1
	for ammo_id in order_ids:
		var def: Dictionary = DataRegistry.get_ammo(ammo_id)
		var dmg = def.get("base_damage", null)
		var dmg_text := "变化" if dmg == null else str(dmg)
		var block := Label.new()
		block.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.text = "%d. %s ×%d\n   基础伤害：%s\n   特殊机制：%s" % [
			idx,
			str(def.get("name", "未知#%d" % ammo_id)),
			int(counts[ammo_id]),
			dmg_text,
			str(def.get("special", ""))
		]
		bag_list.add_child(block)
		idx += 1
	var seq_title := Label.new()
	seq_title.text = "—— 袋内顺序（顶部先抽）——"
	bag_list.add_child(seq_title)
	for i in state.bag.size():
		var def2: Dictionary = DataRegistry.get_ammo(state.bag[i])
		var row := Label.new()
		row.text = "  [%d] %s" % [i + 1, str(def2.get("name", state.bag[i]))]
		bag_list.add_child(row)


func _wire_dev_buttons() -> void:
	%DevAddWhite.pressed.connect(func(): state.dev_add_ammo(CombatConstants.WHITE_AMMO_ID, 1))
	%DevRemoveWhite.pressed.connect(func(): state.dev_remove_ammo(CombatConstants.WHITE_AMMO_ID, 1))
	%DevKill.pressed.connect(func(): state.dev_kill_all_enemies())
	%DevGold.pressed.connect(func(): state.dev_add_gold(10))
	%DevHpUp.pressed.connect(func(): state.dev_set_player_hp(state.player_hp + 5))
	%DevHpDown.pressed.connect(func(): state.dev_set_player_hp(state.player_hp - 5))
	%DevEnemyHp.pressed.connect(func(): state.dev_set_front_enemy_hp(1))
	%DevTPAdj.pressed.connect(func(): state.dev_teleport_front_enemy(1))
	%DevTPFar.pressed.connect(func(): state.dev_teleport_front_enemy(9))
	%DevForceLoad.pressed.connect(func():
		var ids: Array[int] = [
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID
		]
		state.dev_force_load(ids)
	)
	%DevSkipEnemy.pressed.connect(func(): state.dev_skip_enemy_turn())
	%DevClose.pressed.connect(func(): _toggle_dev())
	%DevAddYellow.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_YELLOW, 1))
	%DevAddBlack.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_BLACK, 1))
	%DevAddGreen.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_GREEN, 1))
	%DevAddPurple.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_PURPLE, 1))
	%DevAddRed.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_RED, 1))
	%DevAddBlue.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_BLUE, 1))
	%DevAddGold.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_GOLD, 1))
	%DevAddPink.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_PINK, 1))
	%DevAddBW.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_BW, 1))
	%DevAddPierce.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_PIERCE, 1))
	%DevAddGas.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_GAS, 1))
	%DevAddFire.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_FIRE, 1))
	%DevAddWater.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_WATER, 1))
	%DevAddThunder.pressed.connect(func(): state.dev_add_ammo(FireResolver.ID_THUNDER, 1))


func _refresh() -> void:
	phase_label.text = "阶段：%s" % state.phase_name()
	hp_label.text = "玩家 HP %d / %d" % [state.player_hp, state.player_max_hp]
	bag_label.text = "袋 %d｜弃 %d｜回合 %d" % [state.bag.size(), state.discard.size(), state.turn_index]
	gold_label.text = "金币 %d" % state.gold
	var busy := _firing or state.is_busy_firing()
	btn_load.disabled = busy or not state.can_load()
	btn_fire.disabled = busy or not state.can_fire()
	btn_roll.disabled = busy or not state.can_start_roll()
	btn_unload.disabled = busy or not state.can_unload()
	_refresh_board()
	_refresh_mag()
	if _bag_open:
		_refresh_bag_list()
	match state.phase:
		CombatState.Phase.WON:
			result_label.text = "胜利！敌人全灭"
			result_label.visible = true
		CombatState.Phase.LOST:
			if state.lose_reason == CombatState.LoseReason.AMMO_EXHAUSTED:
				result_label.text = "失败：弹药耗尽"
			else:
				result_label.text = "失败：血量归零"
			result_label.visible = true
		_:
			result_label.visible = false


func _refresh_board() -> void:
	var by_cell := {}
	for e in state.alive_enemies():
		by_cell[e.cell] = e
	for i in CombatConstants.BOARD_SIZE:
		var panel: Panel = board_row.get_child(i)
		var info: Label = panel.get_node("Info")
		var style := StyleBoxFlat.new()
		style.set_border_width_all(2)
		style.border_color = Color(0.2, 0.2, 0.2)
		if i == CombatConstants.PLAYER_CELL:
			style.bg_color = Color(0.2, 0.45, 0.85)
			info.text = "玩家\n%d/%d" % [state.player_hp, state.player_max_hp]
		elif by_cell.has(i):
			var e: EnemyInstance = by_cell[i]
			style.bg_color = Color(0.75, 0.25, 0.25)
			if state.is_adjacent_to_player(e):
				style.border_color = Color(1.0, 0.8, 0.1)
				style.set_border_width_all(3)
			var st := e.status_text()
			info.text = "%s\n%d/%d%s" % [e.name_zh, e.hp, e.max_hp, ("\n" + st) if st != "" else ""]
		else:
			style.bg_color = Color(0.35, 0.35, 0.38)
			info.text = str(i)
		panel.add_theme_stylebox_override("panel", style)


func _refresh_mag() -> void:
	_layout_wheel_chambers()
	var start_i: int = state.magazine.start_index
	for slot_i in CombatConstants.MAGAZINE_SIZE:
		var panel: Panel = _chamber_panels[slot_i]
		var info: Label = panel.get_node("Info")
		var ammo_id: int = state.magazine.slots[slot_i]
		var order_k: int = (slot_i - start_i + CombatConstants.MAGAZINE_SIZE) % CombatConstants.MAGAZINE_SIZE
		var order_num: int = order_k + 1
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(999)
		style.set_border_width_all(2)
		if ammo_id == Magazine.EMPTY:
			style.bg_color = Color(0.22, 0.22, 0.25)
			style.border_color = Color(0.45, 0.45, 0.45)
			info.text = "%d\n空" % order_num
			info.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		else:
			var def: Dictionary = DataRegistry.get_ammo(ammo_id)
			var short := str(def.get("name", ammo_id)).replace("子弹", "")
			style.bg_color = Color(0.9, 0.9, 0.92)
			style.border_color = Color(0.15, 0.15, 0.15)
			info.text = "%d\n%s" % [order_num, short]
			info.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
		if order_k == 0:
			style.border_color = Color(1.0, 0.12, 0.12)
			style.set_border_width_all(3)
			if ammo_id != Magazine.EMPTY:
				style.bg_color = Color(1.0, 0.72, 0.72)
		panel.add_theme_stylebox_override("panel", style)
