extends Control
## 灰盒战斗 UI：棋盘 + 大圆转轮（带六小圆）+ LOAD/FIRE/ROLL/UNLOAD + 检视袋网格/详情 + 胜利奖励 + 开发者工具。
## 转轮：大盘带着仓位整盘旋转（每次 60°）；LOAD 逐步上弹；FIRE 逐发 0.4s；ROLL 旋转到目标仓。

const CELL_W := 96
const CELL_H := 86
const WHEEL_SIZE := 280.0
const CHAMBER_SIZE := 68.0
const WHEEL_RADIUS := 92.0
const DISK_BG_SIZE := 248.0
const FIRE_SHOT_DELAY := 0.4
const STEP_ROT_DURATION := 0.18
const ROLL_ANIM_BASE := 0.32
const ROLL_ANIM_PER_STEP := 0.05
const ROLL_ANIM_MAX := 0.6
const LOAD_INSERT_PAUSE := 0.06
const BAG_GRID_COLS := 4
const BAG_CELL_MIN := Vector2(140, 88)
const VERSION := "0.2.10"

const COL_PHASE := Color(1.0, 0.92, 0.45)
const COL_HP_OK := Color(0.45, 0.95, 0.55)
const COL_HP_LOW := Color(1.0, 0.45, 0.4)
const COL_BAG := Color(0.55, 0.85, 1.0)
const COL_DISCARD := Color(0.85, 0.7, 1.0)
const COL_GOLD := Color(1.0, 0.84, 0.3)
const COL_TURN := Color(0.8, 0.8, 0.85)
const COL_REWARD_TITLE := Color(1.0, 0.95, 0.72)
const COL_REWARD_HINT := Color(0.9, 0.92, 0.98)
const COL_REWARD_BTN := Color(0.98, 0.98, 1.0)

var state: CombatState
var _chamber_panels: Array[Panel] = []
var _disk: Control = null
var _disk_bg: Panel = null
var _bag_open: bool = false
var _dev_open: bool = false
var _detail_open: bool = false
var _firing: bool = false
var _rolling: bool = false
var _loading: bool = false
var _wheel_animating: bool = false
## 盘面视觉步数（整数格的浮点，供 Tween；每步 = 60°）
var _wheel_visual_steps: float = 0.0
var _fire_flash_tween: Tween
var _disk_tween: Tween
var _reward_open: bool = false
var _ammo_detail_panel: PanelContainer = null
var _ammo_detail_body: RichTextLabel = null

@onready var phase_label: Label = %PhaseLabel
@onready var hp_label: Label = %HpLabel
@onready var bag_label: Label = %BagLabel
@onready var discard_label: Label = %DiscardLabel
@onready var gold_label: Label = %GoldLabel
@onready var turn_label: Label = %TurnLabel
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
@onready var btn_next_wave: Button = %BtnNextWave
@onready var bag_panel: PanelContainer = %BagPanel
@onready var bag_list: VBoxContainer = %BagList
@onready var btn_bag_close: Button = %BtnBagClose
@onready var dev_panel: PanelContainer = %DevPanel
@onready var reward_panel: PanelContainer = %RewardPanel
@onready var reward_title: Label = %RewardTitle
@onready var reward_gold_label: Label = %RewardGoldLabel
@onready var reward_hint: Label = %RewardHint
@onready var reward_choices: VBoxContainer = %RewardChoices
@onready var btn_reward_skip: Button = %BtnRewardSkip
@onready var btn_reward_next: Button = %BtnRewardNext
@onready var dimmer: ColorRect = %Dimmer
@onready var version_label: Label = %VersionLabel


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
	btn_next_wave.pressed.connect(_on_next_wave)
	btn_menu.pressed.connect(_on_menu_pressed)
	btn_reward_skip.pressed.connect(_on_reward_skip)
	btn_reward_next.pressed.connect(_on_reward_continue)
	dimmer.gui_input.connect(_on_dimmer_input)
	version_label.text = "v%s" % VERSION
	mag_title.text = "弹夹转轮（大圆带着六仓转 · ▼击发点固定不转 · LOAD 逐发上弹 · 红框=击发仓）"
	_style_overlay_panels()
	_build_board_cells()
	_build_wheel_chambers()
	_build_ammo_detail_panel()
	_wire_dev_buttons()
	bag_panel.visible = false
	dev_panel.visible = false
	reward_panel.visible = false
	dimmer.visible = false
	if RunState.is_in_map_run() and RunState.pending_combat_node_id >= 0:
		state.start_from_run(RunState.combat_snapshot())
		btn_menu.text = "放弃回地图"
	else:
		state.start_graybox()
		btn_menu.text = "返回主菜单"
		btn_next_wave.text = "下一波 NEXT"
	_refresh()


func _style_overlay_panels() -> void:
	for panel in [bag_panel, dev_panel, reward_panel]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.13, 0.18, 0.96)
		style.set_border_width_all(2)
		style.border_color = Color(0.45, 0.55, 0.75, 0.9)
		style.set_corner_radius_all(10)
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 奖励面板必须选完，点遮罩不关闭
		if _reward_open:
			return
		if _detail_open:
			_set_detail_open(false)
			return
		_set_bag_open(false)
		if _dev_open:
			_toggle_dev()


func _on_log(text: String) -> void:
	log_box.append_text(text + "\n")
	# scroll_following=true；再强制滚到底，确保最新行可见
	await get_tree().process_frame
	log_box.scroll_to_line(log_box.get_line_count())


func _build_board_cells() -> void:
	for c in board_row.get_children():
		c.queue_free()
	for i in CombatConstants.BOARD_SIZE:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(CELL_W, CELL_H)
		panel.name = "Cell%d" % i
		var vbox := VBoxContainer.new()
		vbox.name = "VBox"
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vbox.add_theme_constant_override("separation", 2)
		var info := Label.new()
		info.name = "Info"
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.size_flags_vertical = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(info)
		var hp_bar := ProgressBar.new()
		hp_bar.name = "HpBar"
		hp_bar.custom_minimum_size = Vector2(0, 10)
		hp_bar.show_percentage = false
		hp_bar.max_value = 100
		hp_bar.value = 0
		hp_bar.visible = false
		vbox.add_child(hp_bar)
		panel.add_child(vbox)
		board_row.add_child(panel)


func _build_wheel_chambers() -> void:
	_chamber_panels.clear()
	for c in mag_wheel.get_children():
		if c != fire_marker:
			c.queue_free()
	# 可旋转大盘：带着六个小圆仓一起转；击发标是 MagWheel 子节点且不在盘上，屏幕固定。
	_disk = Control.new()
	_disk.name = "Disk"
	_disk.position = Vector2.ZERO
	_disk.size = Vector2(WHEEL_SIZE, WHEEL_SIZE)
	_disk.custom_minimum_size = Vector2(WHEEL_SIZE, WHEEL_SIZE)
	_disk.pivot_offset = Vector2(WHEEL_SIZE, WHEEL_SIZE) * 0.5
	_disk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mag_wheel.add_child(_disk)
	mag_wheel.move_child(_disk, 0)

	_disk_bg = Panel.new()
	_disk_bg.name = "DiskBg"
	_disk_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_pad := (WHEEL_SIZE - DISK_BG_SIZE) * 0.5
	_disk_bg.position = Vector2(bg_pad, bg_pad)
	_disk_bg.size = Vector2(DISK_BG_SIZE, DISK_BG_SIZE)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.16, 0.17, 0.22, 0.95)
	bg_style.set_border_width_all(4)
	bg_style.border_color = Color(0.45, 0.48, 0.55)
	bg_style.set_corner_radius_all(999)
	_disk_bg.add_theme_stylebox_override("panel", bg_style)
	_disk.add_child(_disk_bg)

	var hub := Panel.new()
	hub.name = "Hub"
	hub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hub_sz := 36.0
	hub.position = Vector2(WHEEL_SIZE, WHEEL_SIZE) * 0.5 - Vector2(hub_sz, hub_sz) * 0.5
	hub.size = Vector2(hub_sz, hub_sz)
	var hub_style := StyleBoxFlat.new()
	hub_style.bg_color = Color(0.28, 0.3, 0.36)
	hub_style.set_border_width_all(2)
	hub_style.border_color = Color(0.55, 0.58, 0.65)
	hub_style.set_corner_radius_all(999)
	hub.add_theme_stylebox_override("panel", hub_style)
	_disk.add_child(hub)

	var center := Vector2(WHEEL_SIZE, WHEEL_SIZE) * 0.5
	var n := float(CombatConstants.MAGAZINE_SIZE)
	for i in CombatConstants.MAGAZINE_SIZE:
		var panel := Panel.new()
		panel.name = "Chamber%d" % i
		panel.custom_minimum_size = Vector2(CHAMBER_SIZE, CHAMBER_SIZE)
		panel.size = Vector2(CHAMBER_SIZE, CHAMBER_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var angle: float = -PI / 2.0 + float(i) * TAU / n
		var pos := center + Vector2(cos(angle), sin(angle)) * WHEEL_RADIUS
		panel.position = pos - Vector2(CHAMBER_SIZE, CHAMBER_SIZE) * 0.5
		panel.pivot_offset = Vector2(CHAMBER_SIZE, CHAMBER_SIZE) * 0.5
		var label := Label.new()
		label.name = "Info"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 15)
		panel.add_child(label)
		_disk.add_child(panel)
		_chamber_panels.append(panel)

	fire_marker.text = "▼ 击发"
	fire_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fire_marker.add_theme_color_override("font_color", Color(1.0, 0.18, 0.12))
	fire_marker.add_theme_font_size_override("font_size", 22)
	fire_marker.position = Vector2(WHEEL_SIZE * 0.5 - 40.0, -8.0)
	fire_marker.size = Vector2(80, 28)
	fire_marker.z_index = 5
	fire_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mag_wheel.move_child(fire_marker, mag_wheel.get_child_count() - 1)
	_wheel_visual_steps = 0.0
	_apply_disk_rotation(0.0)


func _apply_disk_rotation(steps: float) -> void:
	_wheel_visual_steps = steps
	if _disk == null:
		return
	_disk.rotation = -steps * TAU / float(CombatConstants.MAGAZINE_SIZE)
	# 文字保持正向，避免整盘转时难读
	for panel in _chamber_panels:
		var info: Label = panel.get_node("Info")
		info.rotation = -_disk.rotation
		info.pivot_offset = panel.size * 0.5


## 顺时针转到目标仓位步数（可跨圈，to 可 > 6）。
func _animate_disk_to(target_steps: float, duration: float) -> void:
	var from_s: float = _wheel_visual_steps
	var to_s: float = target_steps
	# 装填/射击默认顺时针：目标不小于当前（可 +6k）
	while to_s + 0.001 < from_s:
		to_s += float(CombatConstants.MAGAZINE_SIZE)
	if absf(to_s - from_s) < 0.001:
		_apply_disk_rotation(fposmod(to_s, float(CombatConstants.MAGAZINE_SIZE)))
		return
	_wheel_animating = true
	if _disk_tween != null and _disk_tween.is_valid():
		_disk_tween.kill()
	_disk_tween = create_tween()
	_disk_tween.tween_method(_apply_disk_rotation, from_s, to_s, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _disk_tween.finished
	_apply_disk_rotation(fposmod(to_s, float(CombatConstants.MAGAZINE_SIZE)))
	_wheel_animating = false


func _ammo_colors(ammo_id: int) -> Dictionary:
	match ammo_id:
		FireResolver.ID_WHITE:
			return {"bg": Color(0.92, 0.92, 0.94), "fg": Color(0.08, 0.08, 0.1)}
		FireResolver.ID_BLACK:
			return {"bg": Color(0.18, 0.18, 0.2), "fg": Color(0.95, 0.95, 0.95)}
		FireResolver.ID_GREEN:
			return {"bg": Color(0.25, 0.72, 0.35), "fg": Color(0.05, 0.1, 0.05)}
		FireResolver.ID_YELLOW:
			return {"bg": Color(0.95, 0.85, 0.2), "fg": Color(0.15, 0.12, 0.02)}
		FireResolver.ID_PURPLE:
			return {"bg": Color(0.62, 0.35, 0.85), "fg": Color(0.98, 0.95, 1.0)}
		FireResolver.ID_RED:
			return {"bg": Color(0.9, 0.28, 0.28), "fg": Color(1.0, 0.95, 0.95)}
		FireResolver.ID_BLUE:
			return {"bg": Color(0.3, 0.55, 0.95), "fg": Color(0.95, 0.97, 1.0)}
		FireResolver.ID_GOLD:
			return {"bg": Color(0.95, 0.75, 0.15), "fg": Color(0.2, 0.12, 0.02)}
		FireResolver.ID_PINK:
			return {"bg": Color(0.95, 0.55, 0.75), "fg": Color(0.2, 0.05, 0.12)}
		FireResolver.ID_BW:
			return {"bg": Color(0.55, 0.55, 0.58), "fg": Color(0.05, 0.05, 0.05)}
		FireResolver.ID_PIERCE:
			return {"bg": Color(0.7, 0.85, 0.95), "fg": Color(0.05, 0.1, 0.15)}
		FireResolver.ID_GAS:
			return {"bg": Color(0.55, 0.7, 0.25), "fg": Color(0.05, 0.08, 0.02)}
		FireResolver.ID_FIRE:
			return {"bg": Color(1.0, 0.45, 0.15), "fg": Color(0.15, 0.05, 0.0)}
		FireResolver.ID_WATER:
			return {"bg": Color(0.35, 0.7, 0.95), "fg": Color(0.02, 0.08, 0.15)}
		FireResolver.ID_THUNDER:
			return {"bg": Color(0.85, 0.75, 0.2), "fg": Color(0.12, 0.1, 0.0)}
		CombatConstants.INVALID_AMMO_ID:
			return {"bg": Color(0.28, 0.28, 0.3), "fg": Color(0.95, 0.55, 0.55)}
		_:
			return {"bg": Color(0.85, 0.85, 0.88), "fg": Color(0.1, 0.1, 0.1)}


func _busy() -> bool:
	return _firing or _rolling or _loading or _wheel_animating


func _on_load() -> void:
	if _busy():
		return
	_run_load_sequence()


func _run_load_sequence() -> void:
	if not state.begin_load():
		return
	_loading = true
	_refresh()
	# 空袋已在 begin_load 内收尾
	if not state.is_busy_loading():
		_loading = false
		_apply_disk_rotation(float(state.magazine.start_index))
		_refresh()
		return
	while state.is_busy_loading():
		var before_steps: float = _wheel_visual_steps
		var result: Dictionary = state.load_next_chamber()
		if not bool(result.get("ok", false)):
			break
		_refresh_mag()
		_refresh()
		if LOAD_INSERT_PAUSE > 0.0:
			await get_tree().create_timer(LOAD_INSERT_PAUSE).timeout
		var rotate_to: float = float(result.get("rotate_to", state.magazine.start_index))
		# 顺时针转到目标（跨圈用 +6）
		var target: float = rotate_to
		while target + 0.001 < before_steps:
			target += float(CombatConstants.MAGAZINE_SIZE)
		# 若目标相对当前不足一格且未结束，仍转一格
		if not bool(result.get("done", false)) and absf(target - before_steps) < 0.001:
			target = before_steps + 1.0
		if absf(target - before_steps) >= 0.001:
			await _animate_disk_to(target, STEP_ROT_DURATION)
		if bool(result.get("done", false)):
			break
	# 收尾对齐逻辑 start_index（通常 0）
	var final_i: float = float(state.magazine.start_index)
	var align: float = final_i
	while align + 0.001 < _wheel_visual_steps:
		align += float(CombatConstants.MAGAZINE_SIZE)
	if absf(align - _wheel_visual_steps) >= 0.001:
		await _animate_disk_to(align, STEP_ROT_DURATION)
	else:
		_apply_disk_rotation(fposmod(final_i, float(CombatConstants.MAGAZINE_SIZE)))
	_loading = false
	_refresh()


func _on_fire() -> void:
	if _busy():
		return
	_run_fire_sequence()


func _run_fire_sequence() -> void:
	if not state.begin_fire():
		return
	_firing = true
	_refresh()
	while state.phase == CombatState.Phase.FIRING:
		var start_before: int = state.magazine.start_index
		var more: bool = state.fire_next_shot()
		_refresh()
		_flash_fire_chamber()
		var start_after: int = state.magazine.start_index
		if more:
			var delta: int = (start_after - start_before + CombatConstants.MAGAZINE_SIZE) % CombatConstants.MAGAZINE_SIZE
			if delta > 0:
				await _animate_disk_to(_wheel_visual_steps + float(delta), STEP_ROT_DURATION)
			await get_tree().create_timer(FIRE_SHOT_DELAY).timeout
		else:
			break
	_apply_disk_rotation(0.0)
	_firing = false
	_refresh()


func _flash_fire_chamber() -> void:
	if state == null or state.magazine == null:
		return
	var slot_i: int = state.magazine.start_index
	if slot_i < 0 or slot_i >= _chamber_panels.size():
		return
	var panel: Panel = _chamber_panels[slot_i]
	if _fire_flash_tween != null and _fire_flash_tween.is_valid():
		_fire_flash_tween.kill()
	panel.modulate = Color(1.6, 1.4, 0.7)
	_fire_flash_tween = create_tween()
	_fire_flash_tween.tween_property(panel, "modulate", Color.WHITE, 0.28)


func _on_roll() -> void:
	if _busy():
		return
	if not state.can_start_roll():
		return
	_rolling = true
	var before: int = state.magazine.start_index
	_refresh()
	var steps: int = state.apply_roll()
	if steps < 0:
		_rolling = false
		_refresh()
		return
	if steps > 0:
		var dur: float = clampf(ROLL_ANIM_BASE + float(steps) * ROLL_ANIM_PER_STEP, ROLL_ANIM_BASE, ROLL_ANIM_MAX)
		await _animate_disk_to(_wheel_visual_steps + float(steps), dur)
	else:
		_apply_disk_rotation(float(state.magazine.start_index))
	state.resolve_after_player_action()
	_rolling = false
	_refresh()


func _on_unload() -> void:
	if _busy():
		return
	state.do_unload()
	_apply_disk_rotation(0.0)


func _on_menu_pressed() -> void:
	if state.from_map_run:
		# 中途退出：放弃本节点战斗，不完成节点，回地图（保留进战前资源）
		RunState.pending_combat_node_id = -1
		get_tree().change_scene_to_file("res://scenes/map.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_reward_continue() -> void:
	if state.from_map_run:
		_return_to_map(true)
	else:
		_on_next_wave()


func _return_to_map(victory: bool) -> void:
	if victory and not state.can_start_next_wave():
		return
	var payload := state.export_run_payload()
	RunState.apply_combat_result(payload, victory)
	get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_next_wave() -> void:
	if _busy():
		return
	# 地图 run 战败：用下一波按钮返回地图并结束本局
	if state.from_map_run and state.phase == CombatState.Phase.LOST:
		_return_to_map(false)
		return
	if not state.can_start_next_wave():
		return
	state.start_next_wave()
	btn_next_wave.text = "下一波 NEXT"
	_set_reward_open(false)


func _toggle_bag() -> void:
	_set_bag_open(not _bag_open)


func _set_bag_open(open: bool) -> void:
	if open and _reward_open:
		return
	_bag_open = open
	bag_panel.visible = open
	if open:
		_dev_open = false
		dev_panel.visible = false
		_set_detail_open(false)
		_refresh_bag_list()
	else:
		_set_detail_open(false)
	_update_dimmer()


func _toggle_dev() -> void:
	if (not _dev_open) and _reward_open:
		return
	_dev_open = not _dev_open
	dev_panel.visible = _dev_open
	if _dev_open:
		_bag_open = false
		bag_panel.visible = false
	_update_dimmer()


func _update_dimmer() -> void:
	dimmer.visible = _bag_open or _dev_open or _reward_open or _detail_open


func _set_reward_open(open: bool) -> void:
	_reward_open = open
	reward_panel.visible = open
	if open:
		_bag_open = false
		_dev_open = false
		bag_panel.visible = false
		dev_panel.visible = false
		_refresh_reward_panel()
	_update_dimmer()


func _refresh_reward_panel() -> void:
	for c in reward_choices.get_children():
		c.queue_free()
	var pending := state.can_pick_reward()
	var resolved := state.phase == CombatState.Phase.WON and state.reward_resolved
	var enc_title := state.encounter_label() if state != null else "战斗"
	reward_title.text = ("%s胜利 · 选择奖励" % enc_title) if pending else "奖励已领取"
	reward_title.add_theme_color_override("font_color", COL_REWARD_TITLE)
	var base_shown: int = state.last_reward_base_gold if state.last_reward_base_gold > 0 else state.reward_base_gold_for_encounter()
	reward_gold_label.text = "基础金币 +%d 已入账 · 当前金币 %d" % [base_shown, state.gold]
	reward_gold_label.add_theme_color_override("font_color", COL_GOLD)
	reward_hint.add_theme_color_override("font_color", COL_REWARD_HINT)
	_style_reward_action_button(btn_reward_skip)
	_style_reward_action_button(btn_reward_next)
	if pending:
		reward_hint.text = "从下列三发弹药中选一加入弹药袋，或放弃换额外金币 +%d。" % CombatConstants.REWARD_SKIP_EXTRA_GOLD
		btn_reward_skip.visible = true
		btn_reward_skip.text = "放弃三选一 · 换额外金币 +%d" % CombatConstants.REWARD_SKIP_EXTRA_GOLD
		btn_reward_skip.disabled = false
		btn_reward_next.visible = false
		for i in state.reward_choices.size():
			var ammo_id: int = state.reward_choices[i]
			var def: Dictionary = DataRegistry.get_ammo(ammo_id)
			var colors := _ammo_colors(ammo_id)
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 64)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var nm := str(def.get("name", "未知#%d" % ammo_id))
			var desc := str(def.get("special", ""))
			var dmg = def.get("base_damage", "")
			btn.text = "【%d】%s（基础伤 %s）" % [i + 1, nm, str(dmg)]
			if not desc.is_empty():
				btn.tooltip_text = desc
			btn.add_theme_font_size_override("font_size", 22)
			_style_reward_choice_button(btn, colors["bg"])
			var idx := i
			btn.pressed.connect(func(): _on_reward_pick(idx))
			reward_choices.add_child(btn)
	elif resolved:
		if state.from_map_run:
			if state.encounter_kind == CombatState.EncounterKind.BOSS:
				reward_hint.text = "Boss 击败！领取完毕后返回地图查看通关结算。无伤/三回合额外金灰盒暂未结算。"
				btn_reward_next.text = "通关结算 RETURN"
			else:
				reward_hint.text = "领取完毕。返回地图选择下一节点（本战不会再刷下一波）。无伤/三回合额外金灰盒暂未结算。"
				btn_reward_next.text = "返回地图 RETURN"
		else:
			reward_hint.text = "可继续下一波（弹药袋不重置）。练习战无地图。无伤/三回合额外金灰盒暂未结算。"
			btn_reward_next.text = "下一波 NEXT"
		btn_reward_skip.visible = false
		btn_reward_next.visible = true
		btn_reward_next.disabled = not state.can_start_next_wave()
	else:
		reward_hint.text = ""
		btn_reward_skip.visible = false
		btn_reward_next.visible = false


func _apply_light_button_font(btn: Button) -> void:
	btn.add_theme_color_override("font_color", COL_REWARD_BTN)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.95, 0.96, 1.0))
	btn.add_theme_color_override("font_focus_color", COL_REWARD_BTN)
	btn.add_theme_color_override("font_disabled_color", Color(0.78, 0.8, 0.85, 0.85))


func _style_reward_action_button(btn: Button) -> void:
	_apply_light_button_font(btn)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.22, 0.28, 0.42, 1.0)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.7, 0.78, 0.95, 0.95)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color(0.3, 0.38, 0.55, 1.0)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.18, 0.22, 0.34, 1.0)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.16, 0.17, 0.22, 1.0)
	disabled.border_color = Color(0.4, 0.42, 0.48, 0.7)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", disabled)


func _style_reward_choice_button(btn: Button, ammo_bg: Color) -> void:
	_apply_light_button_font(btn)
	# 深色底上用近白字；弹药色只做底色染色，避免沿用深色 fg 导致看不清
	var base := Color(
		clampf(ammo_bg.r * 0.35 + 0.12, 0.0, 1.0),
		clampf(ammo_bg.g * 0.35 + 0.12, 0.0, 1.0),
		clampf(ammo_bg.b * 0.35 + 0.14, 0.0, 1.0),
		1.0
	)
	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.set_border_width_all(2)
	normal.border_color = Color(
		clampf(ammo_bg.r * 0.55 + 0.35, 0.0, 1.0),
		clampf(ammo_bg.g * 0.55 + 0.35, 0.0, 1.0),
		clampf(ammo_bg.b * 0.55 + 0.4, 0.0, 1.0),
		1.0
	)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color(
		clampf(base.r + 0.1, 0.0, 1.0),
		clampf(base.g + 0.1, 0.0, 1.0),
		clampf(base.b + 0.12, 0.0, 1.0),
		1.0
	)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(
		clampf(base.r - 0.04, 0.0, 1.0),
		clampf(base.g - 0.04, 0.0, 1.0),
		clampf(base.b - 0.04, 0.0, 1.0),
		1.0
	)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)


func _on_reward_pick(index: int) -> void:
	if state.pick_reward_ammo(index):
		_refresh_reward_panel()


func _on_reward_skip() -> void:
	if state.skip_reward_for_gold():
		_refresh_reward_panel()


func _refresh_bag_list() -> void:
	for c in bag_list.get_children():
		c.queue_free()
	var inv: Dictionary = state.ammo_inventory_by_id()
	var bag_n: int = state.bag.size()
	var mag_n: int = state.magazine.loaded_count() if state.magazine != null else 0
	var total_n: int = bag_n + mag_n
	var title := Label.new()
	title.text = "完整库存（袋+膛 · 共 %d 发：袋 %d / 膛 %d）｜弃牌 %d｜金币 %d" % [
		total_n, bag_n, mag_n, state.discard.size(), state.gold
	]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 16)
	bag_list.add_child(title)
	if inv.is_empty():
		var empty := Label.new()
		empty.text = "（袋与弹夹皆空）"
		bag_list.add_child(empty)
		var tip0 := Label.new()
		tip0.text = "亮=仍在袋可抽；暗=已上膛。点击格子查看弹药数据与效果。"
		tip0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip0.add_theme_font_size_override("font_size", 13)
		tip0.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		bag_list.add_child(tip0)
		return
	var order_ids: Array[int] = []
	for k in inv.keys():
		order_ids.append(int(k))
	order_ids.sort()
	var grid := GridContainer.new()
	grid.columns = BAG_GRID_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_list.add_child(grid)
	for ammo_id in order_ids:
		var entry: Dictionary = inv[ammo_id]
		var in_bag: int = int(entry.get("bag", 0))
		var in_mag: int = int(entry.get("mag", 0))
		var total: int = int(entry.get("total", in_bag + in_mag))
		var def: Dictionary = DataRegistry.get_ammo(ammo_id)
		var colors := _ammo_colors(ammo_id)
		var cell := PanelContainer.new()
		cell.custom_minimum_size = BAG_CELL_MIN
		var cell_style := StyleBoxFlat.new()
		cell_style.bg_color = colors["bg"]
		cell_style.set_corner_radius_all(8)
		cell_style.set_border_width_all(2)
		cell_style.border_color = Color(0.15, 0.15, 0.18, 0.7)
		if ammo_id == CombatConstants.INVALID_AMMO_ID:
			cell_style.border_color = Color(0.95, 0.35, 0.35)
			cell_style.set_border_width_all(3)
		elif in_mag > 0 and in_bag > 0:
			# 部分上膛：琥珀色描边提示
			cell_style.border_color = Color(0.95, 0.75, 0.25)
			cell_style.set_border_width_all(3)
		elif in_bag == 0 and in_mag > 0:
			cell_style.border_color = Color(0.35, 0.35, 0.4)
		cell_style.content_margin_left = 8
		cell_style.content_margin_right = 8
		cell_style.content_margin_top = 8
		cell_style.content_margin_bottom = 8
		cell.add_theme_stylebox_override("panel", cell_style)
		# 全数已上膛 → 整格变暗；仍有在袋 → 正常亮度
		if in_bag == 0 and in_mag > 0:
			cell.modulate = Color(0.55, 0.55, 0.58, 1.0)
		else:
			cell.modulate = Color.WHITE
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var name_l := Label.new()
		var full_name: String
		if ammo_id == CombatConstants.INVALID_AMMO_ID:
			full_name = CombatConstants.INVALID_AMMO_NAME
		else:
			full_name = str(def.get("name", "未知#%d" % ammo_id))
		var short := full_name.replace("子弹", "").replace("弹药", "")
		name_l.text = short
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_color_override("font_color", colors["fg"])
		name_l.add_theme_font_size_override("font_size", 16)
		var cnt_l := Label.new()
		cnt_l.text = "共×%d" % total
		cnt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cnt_l.add_theme_color_override("font_color", colors["fg"])
		cnt_l.add_theme_font_size_override("font_size", 20)
		var split_l := Label.new()
		split_l.text = "袋%d · 膛%d" % [in_bag, in_mag]
		split_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		split_l.add_theme_font_size_override("font_size", 13)
		if in_mag > 0:
			split_l.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4) if in_bag == 0 else Color(0.45, 0.35, 0.1))
		else:
			split_l.add_theme_color_override("font_color", colors["fg"].darkened(0.15))
		v.add_child(name_l)
		v.add_child(cnt_l)
		v.add_child(split_l)
		cell.add_child(v)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var aid: int = ammo_id
		cell.gui_input.connect(func(ev: InputEvent): _on_bag_cell_input(ev, aid))
		grid.add_child(cell)
	var tip := Label.new()
	tip.text = "亮格=仍有在袋可抽；暗格=该种已全部上膛；黄边=部分上膛。数字「袋/膛」按弹种汇总。点击查看数据与效果。网格不表示抽弹顺序。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	bag_list.add_child(tip)


func _on_bag_cell_input(event: InputEvent, ammo_id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_ammo_detail(ammo_id)


func _build_ammo_detail_panel() -> void:
	_ammo_detail_panel = PanelContainer.new()
	_ammo_detail_panel.name = "AmmoDetailPanel"
	_ammo_detail_panel.visible = false
	_ammo_detail_panel.z_index = 14
	_ammo_detail_panel.set_anchors_preset(Control.PRESET_CENTER)
	_ammo_detail_panel.offset_left = -300.0
	_ammo_detail_panel.offset_top = -220.0
	_ammo_detail_panel.offset_right = 300.0
	_ammo_detail_panel.offset_bottom = 220.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.17, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.7, 0.95, 0.95)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_ammo_detail_panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.name = "DetailTitle"
	title.text = "弹药详情"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	var btn_close := Button.new()
	btn_close.text = "关闭"
	btn_close.custom_minimum_size = Vector2(100, 40)
	btn_close.add_theme_font_size_override("font_size", 18)
	btn_close.pressed.connect(func(): _set_detail_open(false))
	header.add_child(title)
	header.add_child(btn_close)
	_ammo_detail_body = RichTextLabel.new()
	_ammo_detail_body.name = "DetailBody"
	_ammo_detail_body.bbcode_enabled = false
	_ammo_detail_body.fit_content = false
	_ammo_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ammo_detail_body.custom_minimum_size = Vector2(0, 280)
	_ammo_detail_body.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(header)
	vbox.add_child(_ammo_detail_body)
	_ammo_detail_panel.add_child(vbox)
	add_child(_ammo_detail_panel)


func _set_detail_open(open: bool) -> void:
	_detail_open = open
	if _ammo_detail_panel != null:
		_ammo_detail_panel.visible = open
	_update_dimmer()


func _show_ammo_detail(ammo_id: int) -> void:
	if _ammo_detail_body == null:
		return
	_ammo_detail_body.text = DataRegistry.format_ammo_detail_text(ammo_id)
	_set_detail_open(true)


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
	%DevSpawnCivilian.pressed.connect(func(): state.dev_spawn_enemy(1))
	%DevSpawnBandit.pressed.connect(func(): state.dev_spawn_enemy(2))
	%DevSpawnBear.pressed.connect(func(): state.dev_spawn_enemy(3))
	%DevSpawnSkeleton.pressed.connect(func(): state.dev_spawn_enemy(4))
	%DevSpawnStone.pressed.connect(func(): state.dev_spawn_enemy(5))


func _refresh() -> void:
	phase_label.text = "阶段：%s" % state.phase_name()
	phase_label.add_theme_color_override("font_color", COL_PHASE)
	hp_label.text = "HP %d / %d" % [state.player_hp, state.player_max_hp]
	var hp_ratio := float(state.player_hp) / float(maxi(state.player_max_hp, 1))
	hp_label.add_theme_color_override("font_color", COL_HP_LOW if hp_ratio <= 0.35 else COL_HP_OK)
	bag_label.text = "袋 %d" % state.bag.size()
	bag_label.add_theme_color_override("font_color", COL_BAG)
	discard_label.text = "弃 %d" % state.discard.size()
	discard_label.add_theme_color_override("font_color", COL_DISCARD)
	gold_label.text = "金币 %d" % state.gold
	gold_label.add_theme_color_override("font_color", COL_GOLD)
	turn_label.text = "回合 %d · 第 %d 波 · %s" % [state.turn_index, state.wave_index, state.encounter_label()]
	turn_label.add_theme_color_override("font_color", COL_TURN)
	var busy := _busy() or state.is_busy_firing() or state.is_busy_loading()
	btn_load.disabled = busy or not state.can_load()
	btn_fire.disabled = busy or not state.can_fire()
	btn_roll.disabled = busy or not state.can_start_roll()
	btn_unload.disabled = busy or not state.can_unload()
	btn_next_wave.disabled = busy or not state.can_start_next_wave()
	_refresh_board()
	if not _wheel_animating:
		_refresh_mag()
	if _bag_open:
		_refresh_bag_list()
	match state.phase:
		CombatState.Phase.WON:
			if state.reward_pending:
				result_label.text = "本波清空！请选择奖励"
				if not _reward_open:
					_set_reward_open(true)
				elif _reward_open:
					_refresh_reward_panel()
			elif state.reward_resolved:
				if state.from_map_run:
					result_label.text = "奖励已领取 · 请返回地图"
				else:
					result_label.text = "奖励已领取 · 可开下一波"
				if _reward_open:
					_refresh_reward_panel()
			else:
				result_label.text = "本波清空！"
			result_label.visible = true
			# 地图 run：只用奖励面板「返回地图」；练习战显示「下一波」
			btn_next_wave.visible = state.reward_resolved and not state.from_map_run
		CombatState.Phase.LOST:
			if state.lose_reason == CombatState.LoseReason.AMMO_EXHAUSTED:
				result_label.text = "失败：弹药耗尽"
			else:
				result_label.text = "失败：血量归零"
			result_label.visible = true
			if state.from_map_run:
				btn_next_wave.visible = true
				btn_next_wave.text = "返回地图（本局结束）"
				btn_next_wave.disabled = false
			else:
				btn_next_wave.visible = false
			if _reward_open:
				_set_reward_open(false)
		_:
			result_label.visible = false
			btn_next_wave.visible = false
			if _reward_open:
				_set_reward_open(false)


func _refresh_board() -> void:
	var by_cell := {}
	for e in state.alive_enemies():
		by_cell[e.cell] = e
	for i in CombatConstants.BOARD_SIZE:
		var panel: Panel = board_row.get_child(i)
		var info: Label = panel.get_node("VBox/Info")
		var hp_bar: ProgressBar = panel.get_node("VBox/HpBar")
		var style := StyleBoxFlat.new()
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.border_color = Color(0.15, 0.15, 0.18)
		if i == CombatConstants.PLAYER_CELL:
			style.bg_color = Color(0.15, 0.4, 0.85)
			style.border_color = Color(0.55, 0.8, 1.0)
			style.set_border_width_all(3)
			info.text = "玩家\n%d" % state.player_hp
			info.add_theme_color_override("font_color", Color(1, 1, 1))
			info.add_theme_font_size_override("font_size", 18)
			hp_bar.visible = true
			hp_bar.max_value = state.player_max_hp
			hp_bar.value = state.player_hp
			_style_hp_bar(hp_bar, Color(0.35, 0.85, 0.45))
		elif by_cell.has(i):
			var e: EnemyInstance = by_cell[i]
			style.bg_color = Color(0.72, 0.18, 0.2)
			if state.can_attack_player(e):
				style.border_color = Color(1.0, 0.85, 0.15)
				style.set_border_width_all(4)
			else:
				style.border_color = Color(0.95, 0.45, 0.45)
				style.set_border_width_all(2)
			var st := e.status_text()
			var tag_s := ",".join(e.tags) if e.tags.size() > 0 else ""
			info.text = "%s\n%d%s%s" % [
				e.name_zh, e.hp,
				("\n" + tag_s) if tag_s != "" else "",
				("\n" + st) if st != "" else ""
			]
			info.add_theme_color_override("font_color", Color(1, 0.95, 0.95))
			info.add_theme_font_size_override("font_size", 16)
			hp_bar.visible = true
			hp_bar.max_value = maxi(e.max_hp, 1)
			hp_bar.value = e.hp
			_style_hp_bar(hp_bar, Color(0.95, 0.35, 0.3))
		else:
			style.bg_color = Color(0.22, 0.22, 0.26)
			style.border_color = Color(0.32, 0.32, 0.36)
			info.text = str(i)
			info.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
			info.add_theme_font_size_override("font_size", 14)
			hp_bar.visible = false
		panel.add_theme_stylebox_override("panel", style)


func _style_hp_bar(bar: ProgressBar, fill: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)


func _refresh_mag() -> void:
	var start_i: int = state.magazine.start_index
	if not _wheel_animating:
		# 非动画时盘面对齐逻辑起点（保持文字正向）
		var want := float(start_i)
		if absf(fposmod(_wheel_visual_steps, float(CombatConstants.MAGAZINE_SIZE)) - want) > 0.01:
			_apply_disk_rotation(want)
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
			style.bg_color = Color(0.18, 0.18, 0.22)
			style.border_color = Color(0.4, 0.4, 0.45)
			info.text = "%d\n空" % order_num
			info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		else:
			var def: Dictionary = DataRegistry.get_ammo(ammo_id)
			var short: String
			if ammo_id == CombatConstants.INVALID_AMMO_ID:
				short = "无效"
			elif def.is_empty():
				short = str(ammo_id)
			else:
				short = str(def.get("name", ammo_id)).replace("子弹", "").replace("弹药", "")
			var colors := _ammo_colors(ammo_id)
			style.bg_color = colors["bg"]
			style.border_color = Color(0.12, 0.12, 0.14)
			if ammo_id == CombatConstants.INVALID_AMMO_ID:
				style.border_color = Color(0.95, 0.4, 0.4)
			info.text = "%d\n%s" % [order_num, short]
			info.add_theme_color_override("font_color", colors["fg"])
		if order_k == 0:
			style.border_color = Color(1.0, 0.15, 0.12)
			style.set_border_width_all(4)
			if _firing:
				style.bg_color = style.bg_color.lightened(0.25)
		panel.add_theme_stylebox_override("panel", style)
