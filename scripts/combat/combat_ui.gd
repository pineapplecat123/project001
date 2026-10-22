extends Control
## 灰盒战斗 UI：棋盘 + 弹夹 + LOAD/FIRE/ROLL/UNLOAD + 日志。

const CELL_W := 88
const CELL_H := 72
const MAG_W := 64
const MAG_H := 64

var state: CombatState

@onready var phase_label: Label = %PhaseLabel
@onready var hp_label: Label = %HpLabel
@onready var bag_label: Label = %BagLabel
@onready var board_row: HBoxContainer = %BoardRow
@onready var mag_row: HBoxContainer = %MagRow
@onready var log_box: RichTextLabel = %LogBox
@onready var btn_load: Button = %BtnLoad
@onready var btn_fire: Button = %BtnFire
@onready var btn_roll: Button = %BtnRoll
@onready var btn_unload: Button = %BtnUnload
@onready var btn_menu: Button = %BtnMenu
@onready var result_label: Label = %ResultLabel


func _ready() -> void:
	state = CombatState.new()
	state.phase_changed.connect(func(_p): _refresh())
	state.state_changed.connect(_refresh)
	state.log_line.connect(_on_log)
	btn_load.pressed.connect(_on_load)
	btn_fire.pressed.connect(_on_fire)
	btn_roll.pressed.connect(_on_roll)
	btn_unload.pressed.connect(_on_unload)
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	_build_board_cells()
	_build_mag_cells()
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


func _build_mag_cells() -> void:
	for c in mag_row.get_children():
		c.queue_free()
	for i in CombatConstants.MAGAZINE_SIZE:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(MAG_W, MAG_H)
		btn.name = "Mag%d" % i
		btn.pressed.connect(_on_mag_pressed.bind(i))
		mag_row.add_child(btn)


func _on_mag_pressed(index: int) -> void:
	if state.phase == CombatState.Phase.AWAIT_ROLL_PICK:
		state.confirm_roll_start(index)


func _on_load() -> void:
	state.do_load()


func _on_fire() -> void:
	state.do_fire()


func _on_roll() -> void:
	state.begin_roll()


func _on_unload() -> void:
	state.do_unload()


func _refresh() -> void:
	phase_label.text = "阶段：%s" % state.phase_name()
	hp_label.text = "玩家 HP %d / %d" % [state.player_hp, state.player_max_hp]
	bag_label.text = "袋 %d｜弃 %d｜回合 %d" % [state.bag.size(), state.discard.size(), state.turn_index]
	btn_load.disabled = not state.can_load()
	btn_fire.disabled = not state.can_fire()
	btn_roll.disabled = not state.can_start_roll() and state.phase != CombatState.Phase.AWAIT_ROLL_PICK
	btn_unload.disabled = not state.can_unload()
	if state.phase == CombatState.Phase.AWAIT_ROLL_PICK:
		btn_roll.disabled = true
	_refresh_board()
	_refresh_mag()
	match state.phase:
		CombatState.Phase.WON:
			result_label.text = "胜利！敌人全灭"
			result_label.visible = true
		CombatState.Phase.LOST:
			result_label.text = "失败…整局结束"
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
			info.text = "%s\n%d/%d" % [e.name_zh, e.hp, e.max_hp]
		else:
			style.bg_color = Color(0.35, 0.35, 0.38)
			info.text = str(i)
		panel.add_theme_stylebox_override("panel", style)


func _refresh_mag() -> void:
	for i in CombatConstants.MAGAZINE_SIZE:
		var btn: Button = mag_row.get_child(i)
		var ammo_id: int = state.magazine.slots[i]
		var is_start := (i == state.magazine.start_index and ammo_id != Magazine.EMPTY)
		if ammo_id == Magazine.EMPTY:
			btn.text = "空"
			btn.modulate = Color(0.6, 0.6, 0.6)
		else:
			var def: Dictionary = DataRegistry.get_ammo(ammo_id)
			var short := str(def.get("name", ammo_id)).replace("子弹", "")
			btn.text = short
			btn.modulate = Color(0.95, 0.95, 0.95)
		if is_start:
			btn.text = "▶" + btn.text
			btn.modulate = Color(1.0, 0.45, 0.45)
		btn.disabled = state.phase != CombatState.Phase.AWAIT_ROLL_PICK or ammo_id == Magazine.EMPTY
		if state.phase != CombatState.Phase.AWAIT_ROLL_PICK:
			btn.disabled = true
