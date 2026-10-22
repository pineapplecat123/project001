extends Control
## 灰盒战斗 UI：棋盘 + 环形转轮 + LOAD/FIRE/ROLL/UNLOAD + 检视袋网格 + 胜利奖励 + 下一波 + 开发者工具。
## FIRE 逐发 0.4s；ROLL 转轮旋转动画；清场后奖励三选一，结算后再下一波。

const CELL_W := 96
const CELL_H := 86
const WHEEL_SIZE := 280.0
const CHAMBER_SIZE := 68.0
const WHEEL_RADIUS := 92.0
const FIRE_SHOT_DELAY := 0.4
const ROLL_ANIM_BASE := 0.32
const ROLL_ANIM_PER_STEP := 0.04
const ROLL_ANIM_MAX := 0.55
const BAG_GRID_COLS := 4
const BAG_CELL_MIN := Vector2(140, 72)
const VERSION := "0.2.4"

const COL_PHASE := Color(1.0, 0.92, 0.45)
const COL_HP_OK := Color(0.45, 0.95, 0.55)
const COL_HP_LOW := Color(1.0, 0.45, 0.4)
const COL_BAG := Color(0.55, 0.85, 1.0)
const COL_DISCARD := Color(0.85, 0.7, 1.0)
const COL_GOLD := Color(1.0, 0.84, 0.3)
const COL_TURN := Color(0.8, 0.8, 0.85)

var state: CombatState
var _chamber_panels: Array[Panel] = []
var _bag_open: bool = false
var _dev_open: bool = false
var _firing: bool = false
var _rolling: bool = false
var _wheel_animating: bool = false
var _wheel_anim_start: float = 0.0
var _fire_flash_tween: Tween
var _roll_tween: Tween
var _reward_open: bool = false

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
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	btn_reward_skip.pressed.connect(_on_reward_skip)
	btn_reward_next.pressed.connect(_on_next_wave)
	dimmer.gui_input.connect(_on_dimmer_input)
	version_label.text = "v%s" % VERSION
	mag_title.text = "弹夹转轮（▼红标=固定击发点 · 数字=顺时针击发顺序 · ROLL=旋转动画 · 红框=下一发）"
	_style_overlay_panels()
	_build_board_cells()
	_build_wheel_chambers()
	_wire_dev_buttons()
	bag_panel.visible = false
	dev_panel.visible = false
	reward_panel.visible = false
	dimmer.visible = false
	state.start_graybox()
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
	fire_marker.text = "▼ 击发"
	fire_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fire_marker.add_theme_color_override("font_color", Color(1.0, 0.18, 0.12))
	fire_marker.add_theme_font_size_override("font_size", 22)
	fire_marker.position = Vector2(WHEEL_SIZE * 0.5 - 40.0, -4.0)
	fire_marker.size = Vector2(80, 28)
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
		label.add_theme_font_size_override("font_size", 15)
		panel.add_child(label)
		mag_wheel.add_child(panel)
		_chamber_panels.append(panel)
	_layout_wheel_chambers()


func _layout_wheel_chambers() -> void:
	var center := Vector2(WHEEL_SIZE * 0.5, WHEEL_SIZE * 0.5 + 10.0)
	var start_f: float = 0.0
	if _wheel_animating:
		start_f = _wheel_anim_start
	elif state != null and state.magazine != null:
		start_f = float(state.magazine.start_index)
	var n := float(CombatConstants.MAGAZINE_SIZE)
	for slot_i in CombatConstants.MAGAZINE_SIZE:
		var order_k: float = fposmod(float(slot_i) - start_f, n)
		var angle: float = -PI / 2.0 + order_k * TAU / n
		var pos := center + Vector2(cos(angle), sin(angle)) * WHEEL_RADIUS
		var panel: Panel = _chamber_panels[slot_i]
		panel.position = pos - Vector2(CHAMBER_SIZE, CHAMBER_SIZE) * 0.5
		panel.size = Vector2(CHAMBER_SIZE, CHAMBER_SIZE)


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
		_:
			return {"bg": Color(0.85, 0.85, 0.88), "fg": Color(0.1, 0.1, 0.1)}


func _on_load() -> void:
	if _firing or _rolling:
		return
	state.do_load()


func _on_fire() -> void:
	if _firing or _rolling:
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
		_flash_fire_chamber()
		if more:
			await get_tree().create_timer(FIRE_SHOT_DELAY).timeout
		else:
			break
	_firing = false
	_refresh()


func _flash_fire_chamber() -> void:
	if state == null or state.magazine == null:
		return
	var slot_i: int = state.magazine.start_index
	# 刚击发后 start 可能已前进；高亮当前「下一发」仓（order_k==0）
	slot_i = state.magazine.start_index
	if slot_i < 0 or slot_i >= _chamber_panels.size():
		return
	var panel: Panel = _chamber_panels[slot_i]
	if _fire_flash_tween != null and _fire_flash_tween.is_valid():
		_fire_flash_tween.kill()
	panel.modulate = Color(1.6, 1.4, 0.7)
	_fire_flash_tween = create_tween()
	_fire_flash_tween.tween_property(panel, "modulate", Color.WHITE, 0.28)


func _on_roll() -> void:
	if _firing or _rolling:
		return
	if not state.can_start_roll():
		return
	_rolling = true
	var before: int = state.magazine.start_index
	_wheel_animating = true
	_wheel_anim_start = float(before)
	_refresh()
	var steps: int = state.apply_roll()
	if steps < 0:
		_wheel_animating = false
		_rolling = false
		_refresh()
		return
	if steps > 0:
		var dur: float = clampf(ROLL_ANIM_BASE + float(steps) * ROLL_ANIM_PER_STEP, ROLL_ANIM_BASE, ROLL_ANIM_MAX)
		if _roll_tween != null and _roll_tween.is_valid():
			_roll_tween.kill()
		_roll_tween = create_tween()
		_roll_tween.tween_method(_set_wheel_visual_start, float(before), float(before + steps), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await _roll_tween.finished
	_wheel_animating = false
	_wheel_anim_start = float(state.magazine.start_index)
	state.resolve_after_player_action()
	_rolling = false
	_refresh()


func _set_wheel_visual_start(v: float) -> void:
	_wheel_anim_start = v
	_layout_wheel_chambers()


func _on_unload() -> void:
	if _firing or _rolling:
		return
	state.do_unload()


func _on_next_wave() -> void:
	if _firing or _rolling:
		return
	if not state.can_start_next_wave():
		return
	state.start_next_wave()
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
		_refresh_bag_list()
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
	dimmer.visible = _bag_open or _dev_open or _reward_open


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
	reward_title.text = "战斗胜利 · 选择奖励" if pending else "奖励已领取"
	reward_gold_label.text = "基础金币 +%d 已入账 · 当前金币 %d" % [
		CombatConstants.REWARD_BASE_GOLD, state.gold
	]
	reward_gold_label.add_theme_color_override("font_color", COL_GOLD)
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
			btn.add_theme_color_override("font_color", colors["fg"])
			var idx := i
			btn.pressed.connect(func(): _on_reward_pick(idx))
			reward_choices.add_child(btn)
	elif resolved:
		reward_hint.text = "可继续下一波（弹药袋不重置）。无伤/三回合额外金灰盒暂未结算。"
		btn_reward_skip.visible = false
		btn_reward_next.visible = true
		btn_reward_next.disabled = not state.can_start_next_wave()
	else:
		reward_hint.text = ""
		btn_reward_skip.visible = false
		btn_reward_next.visible = false


func _on_reward_pick(index: int) -> void:
	if state.pick_reward_ammo(index):
		_refresh_reward_panel()


func _on_reward_skip() -> void:
	if state.skip_reward_for_gold():
		_refresh_reward_panel()


func _refresh_bag_list() -> void:
	for c in bag_list.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "弹药袋库存（只读 · 共 %d 发 · 抽弹纯随机无顺序）｜弃牌 %d｜金币 %d" % [
		state.bag.size(), state.discard.size(), state.gold
	]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 16)
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
	order_ids.sort()
	var grid := GridContainer.new()
	grid.columns = BAG_GRID_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_list.add_child(grid)
	for ammo_id in order_ids:
		var def: Dictionary = DataRegistry.get_ammo(ammo_id)
		var colors := _ammo_colors(ammo_id)
		var cell := PanelContainer.new()
		cell.custom_minimum_size = BAG_CELL_MIN
		var cell_style := StyleBoxFlat.new()
		cell_style.bg_color = colors["bg"]
		cell_style.set_corner_radius_all(8)
		cell_style.set_border_width_all(2)
		cell_style.border_color = Color(0.15, 0.15, 0.18, 0.7)
		cell_style.content_margin_left = 8
		cell_style.content_margin_right = 8
		cell_style.content_margin_top = 8
		cell_style.content_margin_bottom = 8
		cell.add_theme_stylebox_override("panel", cell_style)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var name_l := Label.new()
		var full_name := str(def.get("name", "未知#%d" % ammo_id))
		var short := full_name.replace("弹药", "")
		name_l.text = short
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_color_override("font_color", colors["fg"])
		name_l.add_theme_font_size_override("font_size", 16)
		var cnt_l := Label.new()
		cnt_l.text = "×%d" % int(counts[ammo_id])
		cnt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cnt_l.add_theme_color_override("font_color", colors["fg"])
		cnt_l.add_theme_font_size_override("font_size", 22)
		v.add_child(name_l)
		v.add_child(cnt_l)
		cell.add_child(v)
		grid.add_child(cell)
	var tip := Label.new()
	tip.text = "格子=弹种库存；装填时从袋内随机抽取，网格不表示抽弹顺序。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	bag_list.add_child(tip)


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
	turn_label.text = "回合 %d · 第 %d 波" % [state.turn_index, state.wave_index]
	turn_label.add_theme_color_override("font_color", COL_TURN)
	var busy := _firing or _rolling or state.is_busy_firing()
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
				result_label.text = "奖励已领取 · 可开下一波"
				if _reward_open:
					_refresh_reward_panel()
			else:
				result_label.text = "本波清空！"
			result_label.visible = true
			btn_next_wave.visible = state.reward_resolved
		CombatState.Phase.LOST:
			if state.lose_reason == CombatState.LoseReason.AMMO_EXHAUSTED:
				result_label.text = "失败：弹药耗尽"
			else:
				result_label.text = "失败：血量归零"
			result_label.visible = true
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
			if state.is_adjacent_to_player(e):
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
			style.bg_color = Color(0.18, 0.18, 0.22)
			style.border_color = Color(0.4, 0.4, 0.45)
			info.text = "%d\n空" % order_num
			info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		else:
			var def: Dictionary = DataRegistry.get_ammo(ammo_id)
			var short := str(def.get("name", ammo_id)).replace("子弹", "")
			var colors := _ammo_colors(ammo_id)
			style.bg_color = colors["bg"]
			style.border_color = Color(0.12, 0.12, 0.14)
			info.text = "%d\n%s" % [order_num, short]
			info.add_theme_color_override("font_color", colors["fg"])
		if order_k == 0:
			style.border_color = Color(1.0, 0.15, 0.12)
			style.set_border_width_all(4)
			if _firing:
				style.bg_color = style.bg_color.lightened(0.25)
		panel.add_theme_stylebox_override("panel", style)
