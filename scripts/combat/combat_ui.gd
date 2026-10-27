extends Control
## 灰盒战斗 UI：棋盘 + 大圆转轮（带六小圆）+ LOAD/FIRE/ROLL/UNLOAD + 右侧常驻弹药袋 + 悬停/长按详情 + 胜利奖励 + 角落开发者工具。
## 转轮：大盘(_disk)带着六小圆整盘转；红击发圈与装弹标挂在 MagWheel 上不转。
## 击发点=正上固定；上弹口=左上固定；LOAD 装左上→转60°；装满后 reroll；FIRE 射正上→转60°。
## 无限模式：每 5 波奖励后进商店（复用 ShopState）；受击飘字带弧线轨迹。

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")
const BagPhysicsBox = preload("res://scripts/combat/bag_physics_box.gd")

const CELL_W := 86
const CELL_H := 110
const UNIT_W := 54.0
const UNIT_H := 70.0
const GROUND_LINE_H := 4.0
const WHEEL_SIZE := 220.0
const CHAMBER_SIZE := 58.0
const WHEEL_RADIUS := 78.0
const DISK_BG_SIZE := 210.0
const FIRE_SHOT_DELAY := 0.4
const FIRE_FLASH_HOLD := 0.2
const POST_FIRE_STATUS_DELAY := 0.45
const STEP_ROT_DURATION := 0.18
const ROLL_ANIM_BASE := 0.45
const ROLL_ANIM_PER_STEP := 0.06
const ROLL_ANIM_MAX := 1.05
const ROLL_VISUAL_EXTRA_TURNS := 1
const LOAD_INSERT_PAUSE := 0.14
## 战斗节奏全局倍率：装弹间隔 / 射击间隔与拖尾飞行 / 转轮旋转 统一除以该值（越大越快）
const COMBAT_SPEED_MIN := 0.5
const COMBAT_SPEED_MAX := 2.0
const COMBAT_SPEED_STEP := 0.25
const COMBAT_SPEED_DEFAULT := 1.0
const BAG_GRID_COLS := 3
const BAG_CELL_MIN := Vector2(56, 56)
const ACTION_BTN_SIZE := 76.0
const LOG_PANEL_MIN := Vector2(154, 280)
const LONG_PRESS_SEC := 0.45
const DETAIL_PANEL_W := 360.0
const DETAIL_PANEL_H := 320.0
const DMG_FLOAT_DURATION := 0.85
const DMG_FLOAT_RISE := 78.0
const DMG_FLOAT_FONT_MIN := 16
const DMG_FLOAT_FONT_MAX := 40
const SHAKE_MIN_PX := 8.0
const SHAKE_MAX_PX := 42.0
const SHAKE_DURATION := 0.28
## 射击轨迹：圆亮彗星头 + 渐隐长尾；芯色=弹药，描边=枪口罪孽
## 尾长相对 v0.2.42/43（300）再加长；开炮瞬间按已飞距离裁切，避免尾巴伸到玩家左侧
const SHOT_TRAIL_LEN := 960.0
const SHOT_TRAIL_THICK := 5.8
const SHOT_OUTLINE_PAD := 2.6
const SHOT_GLOW_PAD := 7.0
const SHOT_COMET_SEGS := 22
const SHOT_HEAD_SIZE := 18.0
const SHOT_HEAD_GLOW := 28.0
const SHOT_TRAVEL_SEC := 0.07
const SHOT_TRAVEL_SEC_PER_CELL := 0.016
const BLOOD_BURST_MIN := 6
const BLOOD_BURST_MAX := 28
const BLOOD_STREAK_SEGS := 8
const BLOOD_STREAK_LEN_MIN := 28.0
const BLOOD_STREAK_LEN_MAX := 72.0

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
var _dev_open: bool = false
var _detail_open: bool = false
var _detail_ammo_id: int = -1
var _hover_ammo_id: int = -1
var _long_press_ammo_id: int = -1
var _long_press_timer: Timer = null
var _detail_from_hover: bool = false
var _detail_from_long_press: bool = false
var _ammo_detail_title: Label = null
var _bag_inv_fingerprint: String = ""
var _bag_physics: BagPhysicsBox = null
var _sin_panel: PanelContainer = null
var _sin_pick_open: bool = false
var _pending_start_endless: bool = false
var _bag_refreshing: bool = false
var _firing: bool = false
var _rolling: bool = false
var _loading: bool = false
var _wheel_animating: bool = false
## 盘面视觉步数（整数格的浮点，供 Tween；每步 = 60°）
var _wheel_visual_steps: float = 0.0
var _fire_flash_tween: Tween
var _disk_tween: Tween
var _fire_ring: Panel = null
var _load_marker: Label = null
var _muzzle_label: Label = null  ## 「枪口：」框外标签
var _muzzle_slot: Control = null  ## 固定占位，防枪口状态撑开 MagCol
var _combat_speed: float = COMBAT_SPEED_DEFAULT
var _speed_row: HBoxContainer = null
var _speed_slider: HSlider = null
var _speed_value_label: Label = null
var _muzzle_panel: PanelContainer = null  ## 透明命中层（悬停/长按）
var _muzzle_chips: HBoxContainer = null
var _muzzle_tip_panel: PanelContainer = null
var _muzzle_tip_body: RichTextLabel = null
var _muzzle_tip_open: bool = false
var _muzzle_tip_from_hover: bool = false
var _muzzle_tip_from_long_press: bool = false
var _long_press_kind: String = ""  ## "ammo" | "muzzle"
## 每格独立抖动 tween（key=cell）；不再整块棋盘抖
var _cell_shake_tweens: Dictionary = {}
## 开火结算时暂存飘字/抖动，等射线飞到再播
var _defer_hit_vfx: bool = false
var _pending_hit_vfx: Array = []
var _reward_open: bool = false
var _ammo_detail_panel: PanelContainer = null
var _ammo_detail_body: RichTextLabel = null
var _shop: ShopState = ShopState.new()
var _shop_open: bool = false
var _shop_panel: PanelContainer = null
var _shop_title: Label = null
var _shop_gold_label: Label = null
var _shop_hint: Label = null
var _shop_stock: VBoxContainer = null
var _shop_bag_list: VBoxContainer = null
var _shop_msg: Label = null
var _btn_shop_reroll: Button = null
var _btn_shop_leave: Button = null

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
var btn_manual_load: Button = null
@onready var btn_fire: Button = %BtnFire
@onready var btn_roll: Button = %BtnRoll
@onready var btn_unload: Button = %BtnUnload
@onready var btn_dev: Button = %BtnDev
@onready var btn_menu: Button = %BtnMenu
@onready var result_label: Label = %ResultLabel
@onready var btn_next_wave: Button = %BtnNextWave
@onready var bag_panel: PanelContainer = %BagPanel
@onready var bag_list: VBoxContainer = %BagList
@onready var bag_header_label: Label = %BagHeaderLabel
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
	state.enemy_damaged.connect(_on_enemy_damaged)
	state.player_damaged.connect(_on_player_damaged)
	state.gold_gained.connect(_on_gold_gained)
	btn_load.pressed.connect(_on_load)
	# btn_manual_load wired in _ensure_square_action_buttons
	btn_fire.pressed.connect(_on_fire)
	btn_roll.pressed.connect(_on_roll)
	btn_unload.pressed.connect(_on_unload)
	btn_dev.pressed.connect(_toggle_dev)
	btn_next_wave.pressed.connect(_on_next_wave)
	btn_menu.pressed.connect(_on_menu_pressed)
	btn_reward_skip.pressed.connect(_on_reward_skip)
	btn_reward_next.pressed.connect(_on_reward_continue)
	dimmer.gui_input.connect(_on_dimmer_input)
	version_label.text = "v%s" % GameVersion.STRING
	mag_title.text = "弹夹转轮"
	var hint_lab: Label = get_node_or_null("%HintLabel") as Label
	if hint_lab != null:
		hint_lab.text = "红圈正上击发 · 左上装弹口 · LOAD一发一转 · 有弹即可 ROLL（不满匣也可）。悬停/长按弹药可看效果。"
	_style_overlay_panels()
	_style_corner_buttons()
	_ensure_long_press_timer()
	_build_board_cells()
	_build_wheel_chambers()
	_build_ammo_detail_panel()
	_build_endless_shop_panel()
	_build_sin_pick_panel()
	_wire_dev_buttons()
	bag_panel.visible = true
	dev_panel.visible = false
	reward_panel.visible = false
	dimmer.visible = false
	_ensure_top_labels_uncropped()
	_ensure_combat_layout()
	_ensure_muzzle_hud()
	_ensure_speed_hud()
	if RunState.is_in_map_run() and RunState.pending_combat_node_id >= 0:
		state.start_from_run(RunState.combat_snapshot())
		btn_menu.text = "放弃回地图"
		state.pace_after_fire = true
		_refresh()
	else:
		_pending_start_endless = RunState.consume_pending_endless()
		btn_menu.text = "返回主菜单"
		btn_next_wave.text = "下一波 NEXT"
		state.pace_after_fire = true
		_open_sin_pick()


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
	# 右侧常驻袋：暖色描边更醒目
	var bag_style := StyleBoxFlat.new()
	bag_style.bg_color = Color(0.14, 0.12, 0.1, 0.94)
	bag_style.set_border_width_all(2)
	bag_style.border_color = Color(0.92, 0.72, 0.35, 0.95)
	bag_style.set_corner_radius_all(10)
	bag_style.content_margin_left = 2
	bag_style.content_margin_right = 2
	bag_style.content_margin_top = 2
	bag_style.content_margin_bottom = 2
	bag_panel.add_theme_stylebox_override("panel", bag_style)
	if bag_header_label != null:
		bag_header_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))


func _style_corner_buttons() -> void:
	for btn in [btn_menu, btn_dev]:
		_apply_light_button_font(btn)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.22, 0.2, 0.16, 0.92)
		normal.set_border_width_all(2)
		normal.border_color = Color(0.85, 0.7, 0.35, 0.9)
		normal.set_corner_radius_all(8)
		normal.content_margin_left = 10
		normal.content_margin_right = 10
		normal.content_margin_top = 6
		normal.content_margin_bottom = 6
		var hover := normal.duplicate()
		hover.bg_color = Color(0.32, 0.28, 0.2, 0.96)
		var pressed := normal.duplicate()
		pressed.bg_color = Color(0.16, 0.14, 0.12, 0.96)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("focus", hover)


func _ensure_top_labels_uncropped() -> void:
	# Noto SC 字形常高出 Label 度量：只加高/加行距，绝不覆盖 font。
	# 旧逻辑用 FontVariation + ThemeDB.fallback_font（无中文）→ 顶栏/弹夹/弹药盒标题全面 hex tofu；
	# 同屏「共15·袋15」未覆盖字体所以正常。保留项目 Theme 的 NotoSansSC-UI。
	# 祖先链关闭裁切；溢出只向下长，避免 grow BOTH 把顶栏顶出视口（y 变负）
	for n: Node in [
		self,
		get_node_or_null("Margin"),
		get_node_or_null("Margin/RootVBox"),
		get_node_or_null("Margin/RootVBox/TopSection"),
		get_node_or_null("Margin/RootVBox/TopSection/TopBarPad"),
		get_node_or_null("Margin/RootVBox/BottomSection"),
	]:
		if n is Control:
			var c := n as Control
			c.clip_contents = false
	# Combat / Margin：顶边钉死，最小高度超出时只往下长
	grow_vertical = Control.GROW_DIRECTION_END
	var margin_c := get_node_or_null("Margin") as Control
	if margin_c != null:
		margin_c.grow_vertical = Control.GROW_DIRECTION_END
	var top_bar: Control = get_node_or_null("%TopBar") as Control
	if top_bar == null:
		top_bar = get_node_or_null("Margin/RootVBox/TopSection/TopBarPad/TopBar") as Control
	if top_bar != null:
		top_bar.clip_contents = false
		top_bar.custom_minimum_size = Vector2(
			top_bar.custom_minimum_size.x,
			maxf(top_bar.custom_minimum_size.y, 36.0)
		)
	var board_title: Label = get_node_or_null("Margin/RootVBox/TopSection/BoardTitle") as Label
	var labels: Array[Label] = [
		phase_label, hp_label, bag_label, discard_label, gold_label, turn_label,
		bag_header_label, board_title, mag_title
	]
	for lab in labels:
		if lab == null:
			continue
		# 不要 add_theme_font_override：必须继续用 ui_theme 的 NotoSansSC-UI
		lab.add_theme_constant_override("line_spacing", 8)
		lab.clip_text = false
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var floor_h := 34.0
		if lab == mag_title:
			floor_h = 24.0
		elif lab == board_title:
			floor_h = 24.0
		elif lab == bag_header_label:
			floor_h = 30.0
		var min_h := maxf(lab.get_minimum_size().y, floor_h)
		lab.custom_minimum_size = Vector2(lab.custom_minimum_size.x, min_h)
	if bag_panel != null:
		bag_panel.clip_contents = false
		var style := bag_panel.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			var flat := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
			flat.content_margin_top = maxf(flat.content_margin_top, 12.0)
			flat.content_margin_left = maxf(flat.content_margin_left, 8.0)
			flat.content_margin_right = maxf(flat.content_margin_right, 8.0)
			flat.content_margin_bottom = maxf(flat.content_margin_bottom, 6.0)
			bag_panel.add_theme_stylebox_override("panel", flat)



func _ensure_combat_layout() -> void:
	## 棋盘居中；底部三块（轮盘+键 | 弹药袋 | 窄日志）均匀成簇，整组画面中央略靠左。
	if board_row != null:
		board_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		board_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var board_title: Label = get_node_or_null("Margin/RootVBox/TopSection/BoardTitle") as Label
	if board_title != null:
		board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		board_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bottom: HBoxContainer = get_node_or_null("Margin/RootVBox/BottomSection") as HBoxContainer
	if bottom == null:
		return
	# 整组（轮盘+袋+日志）相对棋盘再往下一点
	var mid_sp: Control = get_node_or_null("Margin/RootVBox/MidSpacer") as Control
	if mid_sp != null:
		mid_sp.custom_minimum_size = Vector2(0, 32)
	# 三块之间等距；外空白由左右 pad 吸收，不再用中间 EXPAND 拉开
	bottom.add_theme_constant_override("separation", 18)
	var left_pad: Control = bottom.get_node_or_null("BottomLeftPad") as Control
	if left_pad == null:
		left_pad = Control.new()
		left_pad.name = "BottomLeftPad"
		bottom.add_child(left_pad)
	left_pad.visible = true
	left_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_pad.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left_pad.size_flags_stretch_ratio = 0.85  # 略小于右侧 → 整组稍靠左
	left_pad.custom_minimum_size = Vector2.ZERO
	var combat_block: HBoxContainer = bottom.get_node_or_null("CombatBlock") as HBoxContainer
	if combat_block != null:
		combat_block.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		combat_block.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		combat_block.add_theme_constant_override("separation", 14)
		var mag_col: VBoxContainer = combat_block.get_node_or_null("MagCol") as VBoxContainer
		if mag_col != null:
			mag_col.add_theme_constant_override("separation", 6)
		_ensure_square_action_buttons(combat_block)
	if bag_panel != null:
		bag_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bag_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if bag_panel.get_parent() != bottom:
			bag_panel.reparent(bottom)
	_ensure_log_panel_on_right(bottom)
	var right_pad: Control = bottom.get_node_or_null("BagRightPad") as Control
	if right_pad == null:
		right_pad = Control.new()
		right_pad.name = "BagRightPad"
		bottom.add_child(right_pad)
	right_pad.visible = true
	right_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_pad.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_pad.size_flags_stretch_ratio = 1.15
	right_pad.custom_minimum_size = Vector2.ZERO
	# 顺序：左垫 | 轮盘块 | 袋 | 日志 | 右垫（无中间大空白）
	var mid_pad: Control = bottom.get_node_or_null("LogMidPad") as Control
	if mid_pad != null:
		mid_pad.visible = false
		mid_pad.size_flags_horizontal = 0
		mid_pad.custom_minimum_size = Vector2.ZERO
	var log_panel: Node = bottom.get_node_or_null("LogPanel")
	var ordered: Array[Node] = []
	ordered.append(left_pad)
	if combat_block != null:
		ordered.append(combat_block)
	if bag_panel != null:
		ordered.append(bag_panel)
	if log_panel != null:
		ordered.append(log_panel)
	ordered.append(right_pad)
	for i in ordered.size():
		var n: Node = ordered[i]
		if n.get_parent() == bottom:
			bottom.move_child(n, i)
	var footer: VBoxContainer = get_node_or_null("Margin/RootVBox/FooterSection") as VBoxContainer
	if footer != null:
		footer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		footer.add_theme_constant_override("separation", 4)



func _ensure_square_action_buttons(combat_block: HBoxContainer) -> void:
	## 装弹/射击/ROLL/卸除改为 2×2 方形大按钮，更好点按。
	var action_col: VBoxContainer = combat_block.get_node_or_null("ActionCol") as VBoxContainer
	if action_col == null:
		return
	action_col.add_theme_constant_override("separation", 8)
	var grid: GridContainer = action_col.get_node_or_null("ActionGrid") as GridContainer
	if grid == null:
		grid = GridContainer.new()
		grid.name = "ActionGrid"
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		var insert_at := 0
		for i in action_col.get_child_count():
			if str(action_col.get_child(i).name) == "ActionHeader":
				insert_at = i + 1
				break
		action_col.add_child(grid)
		action_col.move_child(grid, insert_at)
	grid.columns = 3
	if btn_manual_load == null:
		btn_manual_load = Button.new()
		btn_manual_load.name = "BtnManualLoad"
		btn_manual_load.pressed.connect(_on_manual_load)
	var specs: Array = [
		[btn_load, "装弹"],
		[btn_manual_load, "手装"],
		[btn_fire, "射击"],
		[btn_roll, "ROLL"],
		[btn_unload, "卸除"],
	]
	for spec in specs:
		var btn: Button = spec[0]
		if btn == null:
			continue
		btn.text = str(spec[1])
		btn.custom_minimum_size = Vector2(ACTION_BTN_SIZE, ACTION_BTN_SIZE)
		btn.add_theme_font_size_override("font_size", 18)
		btn.clip_text = false
		_style_square_action_button(btn)
		if btn.get_parent() == grid:
			pass
		elif btn.get_parent() == null:
			# runtime-created btn (e.g. manual load) has no parent yet; cannot reparent
			grid.add_child(btn)
		else:
			btn.reparent(grid)
	var hint_lab: Label = get_node_or_null("%HintLabel") as Label
	if hint_lab != null and hint_lab.get_parent() == action_col:
		hint_lab.custom_minimum_size = Vector2(ACTION_BTN_SIZE * 2.0 + 8.0, 0)
		hint_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _style_square_action_button(btn: Button) -> void:
	_apply_light_button_font(btn)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.24, 0.34, 0.98)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.75, 0.82, 0.95, 0.95)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = Color(0.3, 0.36, 0.5, 1.0)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.14, 0.18, 0.28, 1.0)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.14, 0.15, 0.18, 0.9)
	disabled.border_color = Color(0.4, 0.42, 0.48, 0.65)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", disabled)


func _ensure_log_panel_on_right(bottom: HBoxContainer) -> void:
	## 战斗日志窄条，与轮盘/袋一起居中成簇。
	var log_panel: PanelContainer = bottom.get_node_or_null("LogPanel") as PanelContainer
	if log_panel == null:
		log_panel = PanelContainer.new()
		log_panel.name = "LogPanel"
		bottom.add_child(log_panel)
	log_panel.custom_minimum_size = LOG_PANEL_MIN
	# 固定窄宽；与轮盘/袋均匀成簇，不独自贴右
	log_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	log_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.15, 0.92)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.48, 0.6, 0.85)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	log_panel.add_theme_stylebox_override("panel", style)
	var margin: MarginContainer = log_panel.get_node_or_null("LogMargin") as MarginContainer
	if margin == null:
		margin = MarginContainer.new()
		margin.name = "LogMargin"
		log_panel.add_child(margin)
	var vbox: VBoxContainer = margin.get_node_or_null("LogVBox") as VBoxContainer
	if vbox == null:
		vbox = VBoxContainer.new()
		vbox.name = "LogVBox"
		vbox.add_theme_constant_override("separation", 4)
		margin.add_child(vbox)
	var footer: Node = get_node_or_null("Margin/RootVBox/FooterSection")
	var log_title: Label = null
	if footer != null:
		log_title = footer.get_node_or_null("LogTitle") as Label
	if log_title == null:
		log_title = vbox.get_node_or_null("LogTitle") as Label
	if log_title == null:
		log_title = Label.new()
		log_title.name = "LogTitle"
		log_title.text = "战斗日志"
	if log_title.get_parent() != vbox:
		log_title.reparent(vbox)
		vbox.move_child(log_title, 0)
	log_title.add_theme_font_size_override("font_size", 14)
	log_title.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9, 1))
	if log_box != null:
		if log_box.get_parent() != vbox:
			log_box.reparent(vbox)
		log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		log_box.custom_minimum_size = Vector2(0, 220)
	# 排序由 _ensure_combat_layout 统一处理；此处只保证窄宽、不 expand
	var mid_pad: Control = bottom.get_node_or_null("LogMidPad") as Control
	if mid_pad != null:
		mid_pad.visible = false
		mid_pad.size_flags_horizontal = 0
		mid_pad.custom_minimum_size = Vector2.ZERO


func _ensure_muzzle_hud() -> void:
	if _muzzle_slot != null:
		return
	# 固定槽：框外「枪口：」+ 每状态一颗小芯片；高度锁死不撑 MagCol
	_muzzle_slot = Control.new()
	_muzzle_slot.name = "MuzzleStatusSlot"
	_muzzle_slot.custom_minimum_size = Vector2(220, 26)
	_muzzle_slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_muzzle_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_muzzle_slot.clip_contents = true
	_muzzle_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.name = "MuzzleStatusRow"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_muzzle_label = Label.new()
	_muzzle_label.name = "MuzzleStatusTitle"
	_muzzle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_muzzle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_muzzle_label.add_theme_font_size_override("font_size", 12)
	_muzzle_label.add_theme_color_override("font_color", Color(0.78, 0.76, 0.72))
	_muzzle_label.text = "枪口："
	row.add_child(_muzzle_label)
	_muzzle_chips = HBoxContainer.new()
	_muzzle_chips.name = "MuzzleStatusChips"
	_muzzle_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_muzzle_chips.add_theme_constant_override("separation", 3)
	_muzzle_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_muzzle_chips)
	_muzzle_slot.add_child(row)
	# 透明命中层盖在整行上，供悬停/长按提示（不画大框）
	_muzzle_panel = PanelContainer.new()
	_muzzle_panel.name = "MuzzleStatusHit"
	_muzzle_panel.z_index = 5
	_muzzle_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_muzzle_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hit_style := StyleBoxEmpty.new()
	_muzzle_panel.add_theme_stylebox_override("panel", hit_style)
	_muzzle_slot.add_child(_muzzle_panel)
	var mag_col: Node = mag_title.get_parent() if mag_title != null else self
	if mag_col != null:
		mag_col.add_child(_muzzle_slot)
		if mag_title != null:
			mag_col.move_child(_muzzle_slot, mag_title.get_index() + 1)
	else:
		add_child(_muzzle_slot)
	_muzzle_panel.mouse_entered.connect(_on_muzzle_hover_enter)
	_muzzle_panel.mouse_exited.connect(_on_muzzle_hover_exit)
	_muzzle_panel.gui_input.connect(_on_muzzle_gui_input)
	_build_muzzle_tip_panel()


func _refresh_muzzle_hud() -> void:
	if _muzzle_chips == null or state == null:
		return
	for c in _muzzle_chips.get_children():
		_muzzle_chips.remove_child(c)
		c.queue_free()
	var parts := state.muzzle_status_parts()
	if parts.is_empty():
		var empty := Label.new()
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.55, 0.53, 0.5))
		empty.text = "—"
		_muzzle_chips.add_child(empty)
	else:
		for name in parts:
			_muzzle_chips.add_child(_make_muzzle_chip(str(name)))
	if _muzzle_slot != null:
		_muzzle_slot.visible = true
	if _muzzle_tip_open:
		_refresh_muzzle_tip_body()


func _make_muzzle_chip(name: String) -> PanelContainer:
	## 单个枪口状态小框：只显示名字，字小边距紧。
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.26, 0.1, 0.06, 0.95)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 0.55, 0.22, 0.95)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", style)
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.text = name
	lab.add_theme_font_size_override("font_size", 11)
	lab.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	chip.add_child(lab)
	return chip


func _paced(sec: float) -> float:
	## 全局战斗速度：秒数 / 倍率；2× → 等待减半，0.5× → 等待加倍。
	return maxf(sec / maxf(_combat_speed, 0.01), 0.0)


func _ensure_speed_hud() -> void:
	if _speed_row != null:
		return
	_speed_row = HBoxContainer.new()
	_speed_row.name = "CombatSpeedRow"
	_speed_row.custom_minimum_size = Vector2(220, 28)
	_speed_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_speed_row.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "速度"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	title.custom_minimum_size = Vector2(36, 0)
	_speed_row.add_child(title)
	_speed_slider = HSlider.new()
	_speed_slider.name = "CombatSpeedSlider"
	_speed_slider.min_value = COMBAT_SPEED_MIN
	_speed_slider.max_value = COMBAT_SPEED_MAX
	_speed_slider.step = COMBAT_SPEED_STEP
	_speed_slider.value = COMBAT_SPEED_DEFAULT
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.custom_minimum_size = Vector2(100, 22)
	_speed_slider.value_changed.connect(_on_combat_speed_changed)
	_speed_row.add_child(_speed_slider)
	_speed_value_label = Label.new()
	_speed_value_label.name = "CombatSpeedValue"
	_speed_value_label.custom_minimum_size = Vector2(44, 0)
	_speed_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_value_label.add_theme_font_size_override("font_size", 14)
	_speed_value_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_speed_value_label.text = "1.0×"
	_speed_row.add_child(_speed_value_label)
	var mag_col: Node = mag_title.get_parent() if mag_title != null else self
	if mag_col != null:
		mag_col.add_child(_speed_row)
		# 放在 MagWheel 下方，玩家摸得到；固定高度不顶开其它列
		var wheel: Node = mag_col.get_node_or_null("MagWheel")
		if wheel != null:
			mag_col.move_child(_speed_row, wheel.get_index() + 1)
	else:
		add_child(_speed_row)


func _on_combat_speed_changed(v: float) -> void:
	_combat_speed = clampf(v, COMBAT_SPEED_MIN, COMBAT_SPEED_MAX)
	if _speed_value_label != null:
		_speed_value_label.text = "%s×" % String.num(_combat_speed, 2)


func _ensure_long_press_timer() -> void:
	if _long_press_timer != null:
		return
	_long_press_timer = Timer.new()
	_long_press_timer.name = "AmmoLongPressTimer"
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = LONG_PRESS_SEC
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 奖励 / 无限商店必须主动操作，点遮罩不关闭
		if _reward_open or _shop_open or _sin_pick_open:
			return
		if _detail_open and not _detail_from_hover:
			_hide_ammo_detail()
			return
		if _dev_open:
			_toggle_dev()


func _on_log(text: String) -> void:
	log_box.append_text(text + "\n")
	# scroll_following=true；再强制滚到底，确保最新行可见
	await get_tree().process_frame
	log_box.scroll_to_line(log_box.get_line_count())


func _unit_rest_position() -> Vector2:
	## 单位底边贴在格内地面线段顶边。
	return Vector2((CELL_W - UNIT_W) * 0.5, float(CELL_H) - UNIT_H - GROUND_LINE_H)


func _build_board_cells() -> void:
	## 视觉：每格底一条地面线段拼成整线 + 线上站立的单位块；格位逻辑仍按 cell 索引。
	## 不用 VBox 兄弟节点画线（容器布局会抢 position → 线闪/消失）。
	for c in board_row.get_children():
		c.queue_free()
	_remove_legacy_ground_line()
	# 格间距 0，地面线段首尾相接成连续线
	board_row.add_theme_constant_override("separation", 0)
	for i in CombatConstants.BOARD_SIZE:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(CELL_W, CELL_H)
		slot.name = "Cell%d" % i
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ground := ColorRect.new()
		ground.name = "GroundSeg"
		ground.color = Color(0.78, 0.72, 0.55, 0.95)
		ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground.position = Vector2(0.0, float(CELL_H) - GROUND_LINE_H)
		ground.size = Vector2(CELL_W, GROUND_LINE_H)
		slot.add_child(ground)
		# 格位透明占位；单位本体是 UnitBody（用 position 贴地，抖动也改 position）
		var unit := Panel.new()
		unit.name = "UnitBody"
		unit.visible = false
		unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unit.custom_minimum_size = Vector2(UNIT_W, UNIT_H)
		unit.size = Vector2(UNIT_W, UNIT_H)
		unit.position = _unit_rest_position()
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
		hp_bar.custom_minimum_size = Vector2(0, 8)
		hp_bar.show_percentage = false
		hp_bar.max_value = 100
		hp_bar.value = 0
		hp_bar.visible = false
		vbox.add_child(hp_bar)
		unit.add_child(vbox)
		slot.add_child(unit)
		board_row.add_child(slot)


func _remove_legacy_ground_line() -> void:
	## 清掉 v0.2.34 挂在 TopSection(VBox) 上的 GroundLine，避免与容器布局打架。
	if board_row == null or board_row.get_parent() == null:
		return
	var parent: Node = board_row.get_parent()
	var line: Node = parent.get_node_or_null("GroundLine")
	if line != null:
		line.queue_free()
	if board_row.resized.is_connected(_layout_ground_line):
		board_row.resized.disconnect(_layout_ground_line)


func _ensure_ground_line() -> void:
	## 兼容旧调用：地面已改每格 GroundSeg，只需清遗留兄弟线。
	_remove_legacy_ground_line()


func _layout_ground_line() -> void:
	## 兼容旧调用：每格 GroundSeg 固定在槽底，无需按 BoardRow rect 重算。
	pass


func _build_wheel_chambers() -> void:
	_chamber_panels.clear()
	mag_wheel.custom_minimum_size = Vector2(WHEEL_SIZE, WHEEL_SIZE)
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
	var hub_sz := 30.0
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
		label.add_theme_font_size_override("font_size", 13)
		panel.add_child(label)
		_disk.add_child(panel)
		_chamber_panels.append(panel)

	# —— 屏幕固定层（parent=MagWheel，不随 _disk 转）——
	# 红色击发指示圈：正上方，永远不动
	if _fire_ring != null and is_instance_valid(_fire_ring):
		_fire_ring.queue_free()
	_fire_ring = Panel.new()
	_fire_ring.name = "FireRing"
	_fire_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_sz := CHAMBER_SIZE + 10.0
	var top_pos := Vector2(WHEEL_SIZE, WHEEL_SIZE) * 0.5 + Vector2(0, -WHEEL_RADIUS) - Vector2(ring_sz, ring_sz) * 0.5
	_fire_ring.position = top_pos
	_fire_ring.size = Vector2(ring_sz, ring_sz)
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0, 0, 0, 0)
	ring_style.set_border_width_all(4)
	ring_style.border_color = Color(1.0, 0.15, 0.12, 1.0)
	ring_style.set_corner_radius_all(999)
	_fire_ring.add_theme_stylebox_override("panel", ring_style)
	_fire_ring.z_index = 4
	mag_wheel.add_child(_fire_ring)

	# 只留红圈；去掉「▼ 击发」红字
	if fire_marker != null:
		fire_marker.visible = false
		fire_marker.text = ""
		fire_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 左上装弹口标（固定）
	if _load_marker != null and is_instance_valid(_load_marker):
		_load_marker.queue_free()
	_load_marker = Label.new()
	_load_marker.name = "LoadMarker"
	_load_marker.text = "装→"
	_load_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_marker.add_theme_color_override("font_color", Color(0.45, 0.95, 0.75))
	_load_marker.add_theme_font_size_override("font_size", 18)
	# 左上仓位中心：angle = -PI/2 - PI/3 = -5PI/6
	var load_angle := -PI / 2.0 - PI / 3.0
	var load_center := Vector2(WHEEL_SIZE, WHEEL_SIZE) * 0.5 + Vector2(cos(load_angle), sin(load_angle)) * (WHEEL_RADIUS + 36.0)
	_load_marker.position = load_center - Vector2(28, 12)
	_load_marker.size = Vector2(56, 24)
	_load_marker.z_index = 5
	_load_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mag_wheel.add_child(_load_marker)

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
		FireResolver.ID_WRATH:
			return {"bg": Color(0.75, 0.12, 0.12), "fg": Color(1.0, 0.92, 0.9)}
		FireResolver.ID_PRIDE:
			return {"bg": Color(0.55, 0.35, 0.85), "fg": Color(0.98, 0.95, 1.0)}
		FireResolver.ID_GREED:
			return {"bg": Color(0.2, 0.65, 0.35), "fg": Color(0.95, 1.0, 0.95)}
		CombatConstants.INVALID_AMMO_ID:
			return {"bg": Color(0.28, 0.28, 0.3), "fg": Color(0.95, 0.55, 0.55)}
		_:
			return {"bg": Color(0.85, 0.85, 0.88), "fg": Color(0.1, 0.1, 0.1)}


func _busy() -> bool:
	return _firing or _rolling or _loading or _wheel_animating or _sin_pick_open


func _on_load() -> void:
	if _busy():
		return
	_run_load_sequence()


func _run_load_sequence() -> void:
	if not state.begin_load():
		return
	_loading = true
	# 开局：仓 0 在左上上弹口 → start_index = LOAD_SESSION_INITIAL_START
	_apply_disk_rotation(float(state.magazine.start_index))
	_refresh_mag_contents()
	_refresh_hud_only()
	if not state.is_busy_loading():
		_loading = false
		_apply_disk_rotation(float(state.magazine.start_index))
		_refresh()
		return
	var needs_spin := false
	while state.is_busy_loading():
		var before_steps: float = _wheel_visual_steps
		var result: Dictionary = state.load_next_chamber()
		if not bool(result.get("ok", false)):
			break
		needs_spin = bool(result.get("needs_spin", false))
		# 关键：盘面仍停在 before_steps，写入的仓正对 ◀装 标注
		_refresh_mag_contents()
		_refresh_hud_only()
		if LOAD_INSERT_PAUSE > 0.0:
			await get_tree().create_timer(_paced(LOAD_INSERT_PAUSE)).timeout
		if bool(result.get("done", false)):
			break
		# 入弹可见后再逻辑转盘 + Tween 60°（先占住 _wheel_animating，避免 signal refresh 按新 start 误高亮）
		var rotate_to: float = float(result.get("rotate_to", state.magazine.start_index))
		var target: float = rotate_to
		while target + 0.001 < before_steps:
			target += float(CombatConstants.MAGAZINE_SIZE)
		if absf(target - before_steps) < 0.001:
			target = before_steps + 1.0
		_wheel_animating = true
		state.apply_load_rotate()
		await _animate_disk_to(target, _paced(STEP_ROT_DURATION))
		_refresh_mag_contents()
	# 装满后：与 ROLL 按钮同一套随机转（_run_shared_cylinder_spin）
	if needs_spin and state.can_start_roll():
		await _run_shared_cylinder_spin()
	else:
		_apply_disk_rotation(float(state.magazine.start_index))
	_loading = false
	_refresh()


func _on_manual_load() -> void:
	if _busy():
		return
	if not state.can_manual_load():
		if state.bag.is_empty():
			state._log("手装：弹药袋已空。")
		elif state.is_busy_loading() and state.magazine != null and state.magazine.loaded_count() >= CombatConstants.MAGAZINE_SIZE:
			state._log("手装：弹匣已满。")
		else:
			state._log("手装：当前无法装填。")
		_refresh()
		return
	_run_manual_load_one()


func _run_manual_load_one() -> void:
	## 与装弹相同路径，但只装 1 发后停（会话可继续手装）。
	_loading = true
	if not state.is_busy_loading():
		if not state.begin_load():
			_loading = false
			_refresh()
			return
		_apply_disk_rotation(float(state.magazine.start_index))
		_refresh_mag_contents()
		_refresh_hud_only()
	var before_steps: float = _wheel_visual_steps
	var result: Dictionary = state.load_next_chamber()
	if not bool(result.get("ok", false)):
		_loading = false
		_refresh()
		return
	_refresh_mag_contents()
	_refresh_hud_only()
	if LOAD_INSERT_PAUSE > 0.0:
		await get_tree().create_timer(_paced(LOAD_INSERT_PAUSE)).timeout
	var done: bool = bool(result.get("done", false))
	if not done:
		var rotate_to: float = float(result.get("rotate_to", state.magazine.start_index))
		var target: float = rotate_to
		while target + 0.001 < before_steps:
			target += float(CombatConstants.MAGAZINE_SIZE)
		if absf(target - before_steps) < 0.001:
			target = before_steps + 1.0
		_wheel_animating = true
		state.apply_load_rotate()
		await _animate_disk_to(target, _paced(STEP_ROT_DURATION))
		_refresh_mag_contents()
	else:
		# 装满结束：与整匣装相同，可随机转
		if bool(result.get("needs_spin", false)) and state.can_start_roll():
			await _run_shared_cylinder_spin()
		else:
			_apply_disk_rotation(float(state.magazine.start_index))
	_loading = false
	_refresh()


func _animate_gold_extra_load() -> void:
	## 金色额外轮：一发发装入转轮，节奏对齐普通 LOAD（入弹停顿 + 60° 旋转）；装满可再 spin。
	_loading = true
	_apply_disk_rotation(float(state.magazine.start_index))
	_refresh_mag_contents()
	_refresh_hud_only()
	if not state.is_busy_loading():
		_loading = false
		_apply_disk_rotation(float(state.magazine.start_index))
		_refresh_hud_only()
		return
	var needs_spin := false
	while state.is_busy_loading():
		var before_steps: float = _wheel_visual_steps
		var result: Dictionary = state.load_next_chamber()
		if not bool(result.get("ok", false)):
			break
		needs_spin = bool(result.get("needs_spin", false))
		_refresh_mag_contents()
		_refresh_hud_only()
		if LOAD_INSERT_PAUSE > 0.0:
			await get_tree().create_timer(_paced(LOAD_INSERT_PAUSE)).timeout
		if bool(result.get("done", false)):
			break
		var rotate_to: float = float(result.get("rotate_to", state.magazine.start_index))
		var target: float = rotate_to
		while target + 0.001 < before_steps:
			target += float(CombatConstants.MAGAZINE_SIZE)
		if absf(target - before_steps) < 0.001:
			target = before_steps + 1.0
		_wheel_animating = true
		state.apply_load_rotate()
		await _animate_disk_to(target, _paced(STEP_ROT_DURATION))
		_refresh_mag_contents()
	if needs_spin and state.can_start_roll():
		await _run_shared_cylinder_spin()
	else:
		_apply_disk_rotation(float(state.magazine.start_index))
	_loading = false
	_refresh_mag_contents()
	_refresh_hud_only()


func _on_fire() -> void:
	if _busy():
		return
	_run_fire_sequence()


func _run_fire_sequence() -> void:
	if not state.begin_fire():
		return
	_firing = true
	await _animate_fire_shots()
	# 金色额外轮：逐步装弹（同普通装弹节奏）→ 再自动开火（不瞬装满）
	while state.pending_gold_autofires() > 0:
		if not state.begin_gold_extra_load():
			break
		await _animate_gold_extra_load()
		if state.magazine.is_empty() or not state.can_fire():
			break
		await get_tree().create_timer(_paced(FIRE_SHOT_DELAY * 0.5)).timeout
		if not state.begin_fire():
			break
		await _animate_fire_shots()
	# 射击序列结束 → 可见间隔 → 再结算怪回合（含流血等状态伤）
	if state.post_fire_enemy_pending():
		await get_tree().create_timer(_paced(POST_FIRE_STATUS_DELAY)).timeout
		state.resolve_post_fire_enemy_turn()
	if state.has_corpse_enemies():
		state.flush_dead_enemies()
	_apply_disk_rotation(float(state.magazine.start_index))
	_firing = false
	_refresh()


func _animate_fire_shots() -> void:
	## 红圈固定正上；盘面先对齐当前击发仓；动画期间禁止 _refresh_mag 抢跑对齐。
	## 半满/锤位空仓：先播可见旋转到最近有弹格，再黄闪击发，再转 60°；不瞬跳。
	_apply_disk_rotation(float(state.magazine.start_index))
	_refresh_mag_contents()
	_refresh_hud_only()
	while state.phase == CombatState.Phase.FIRING:
		var start_before: int = state.magazine.start_index
		# 结算前锁视觉步数=锤位；signal refresh 不得抢跑
		_apply_disk_rotation(float(start_before))
		_wheel_animating = true
		var skip_n: int = state.peek_blank_skip_steps()
		if skip_n > 0:
			# 每空仓一格时长，总时长随步数变长，保证能看见转到有弹处
			var skip_dur: float = _paced(STEP_ROT_DURATION) * float(skip_n)
			await _animate_disk_to(_wheel_visual_steps + float(skip_n), skip_dur)
			_refresh_mag_contents()
		_pending_hit_vfx.clear()
		# 不 defer 飘字：pace 下扣血在命中帧，enemy_damaged 当场飘字
		_defer_hit_vfx = false
		var more: bool = state.fire_next_shot()
		# fire_next_shot 内会瞬推 skip_n（与上面动画对齐）并消耗实弹后再 +1
		var fired_slot: int = state.last_fired_slot
		var blank: bool = state.last_shot_was_blank
		skip_n = int(state.last_blank_skip_steps)
		if not blank:
			_flash_fire_at_top(fired_slot)
			_refresh_mag_contents()
			# 只刷转轮/顶栏；怪 HP 仍是开火前，等拖尾命中再变
			_refresh_hud_only()
			# 实弹：彗星拖尾飞掠；途经命中帧结算伤害+飚血+飘字
			await _play_shot_beam_and_impact()
			if state.has_paced_shot_pending():
				state.finalize_paced_shot()
			_pending_hit_vfx.clear()
			# 飚血已在怪还在场时播完；现在再清尸体
			if state.has_corpse_enemies():
				state.flush_dead_enemies()
			else:
				_refresh_board()
			await get_tree().create_timer(_paced(FIRE_FLASH_HOLD)).timeout
		else:
			if state.has_paced_shot_pending():
				state.finalize_paced_shot()
			_pending_hit_vfx.clear()
			_refresh_mag_contents()
			_refresh_hud_only()
		if more:
			# 跳空已在击发前播完；此处只播消耗后固定 60°
			var start_after: int = state.magazine.start_index
			var expected_visual: int = (start_before + skip_n) % CombatConstants.MAGAZINE_SIZE
			var remain: int = (start_after - expected_visual + CombatConstants.MAGAZINE_SIZE) % CombatConstants.MAGAZINE_SIZE
			if remain == 0:
				remain = 1
			await _animate_disk_to(_wheel_visual_steps + float(remain), _paced(STEP_ROT_DURATION))
			_refresh_mag_contents()
			await get_tree().create_timer(_paced(FIRE_SHOT_DELAY)).timeout
		else:
			_wheel_animating = false
			break
	_apply_disk_rotation(float(state.magazine.start_index))


func _cell_unit_global_center(cell: int) -> Vector2:
	## 棋盘单位块中心（全球坐标）；无单位则用格中心。
	if board_row == null or cell < 0 or cell >= board_row.get_child_count():
		return Vector2.ZERO
	var slot: Control = board_row.get_child(cell) as Control
	if slot == null:
		return Vector2.ZERO
	var unit: Control = slot.get_node_or_null("UnitBody") as Control
	if unit != null and unit.visible:
		return unit.get_global_rect().get_center()
	return slot.get_global_rect().get_center()


func _play_shot_beam_and_impact() -> void:
	## 圆亮彗星从玩家单位飞向命中怪；穿透则飞到沿途最后一命中格，途经各怪飚血。
	if state == null:
		return
	var hit_cells: Array = state.last_shot_hit_cells.duplicate()
	var hit_amts: Array = state.last_shot_hit_amounts.duplicate()
	if hit_cells.is_empty() and int(state.last_shot_hit_cell) >= 0:
		hit_cells = [int(state.last_shot_hit_cell)]
		hit_amts = [int(state.last_shot_dealt)]
	if hit_cells.is_empty():
		return
	var from_g: Vector2 = _cell_unit_global_center(CombatConstants.PLAYER_CELL)
	var end_cell: int = int(hit_cells[hit_cells.size() - 1])
	var to_g: Vector2 = _cell_unit_global_center(end_cell)
	if from_g == Vector2.ZERO or to_g == Vector2.ZERO:
		return
	var ammo_id: int = int(state.last_shot_ammo_id)
	var core_col: Color = _ammo_colors(ammo_id).get("bg", Color(0.95, 0.95, 0.9))
	var outline_cols: Array[Color] = []
	for mid in state.last_shot_muzzle_outline_ids:
		outline_cols.append(_ammo_colors(int(mid)).get("bg", Color(1, 1, 1)))
	# 途经点：用于飞行中按时飚血
	var waypoints: Array = []
	for i in hit_cells.size():
		var c: int = int(hit_cells[i])
		var g: Vector2 = _cell_unit_global_center(c)
		var amt: int = int(hit_amts[i]) if i < hit_amts.size() else 0
		waypoints.append({"g": g, "amount": amt, "cell": c, "hit_index": i})
	var travel: float = _paced(SHOT_TRAVEL_SEC + SHOT_TRAVEL_SEC_PER_CELL * float(maxi(hit_cells.size() - 1, 0)))
	await _animate_shot_projectile(from_g, to_g, core_col, outline_cols, waypoints, travel)


func _animate_shot_projectile(
	from_g: Vector2, to_g: Vector2, core_col: Color, outline_cols: Array[Color],
	waypoints: Array, travel_sec: float
) -> void:
	## 圆亮彗星头 + 渐隐长尾，从玩家单位飞向目标；开炮瞬间裁切尾巴，不从屏幕左侧伸进来。
	var delta: Vector2 = to_g - from_g
	if delta.length_squared() < 0.01:
		delta = Vector2.RIGHT
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.z_index = 48
	add_child(host)
	host.global_position = from_g
	host.rotation = delta.angle()
	var n_out: int = outline_cols.size()
	var trail_parts: Array = []
	var seg_w: float = SHOT_TRAIL_LEN / float(SHOT_COMET_SEGS)
	# 尾→头：更实的渐隐尾（整体不透明度抬高）
	for si in SHOT_COMET_SEGS:
		var u: float = float(si) / float(maxi(SHOT_COMET_SEGS - 1, 1))  # 0=最尾，1=近头
		var alpha: float = lerpf(0.38, 0.95, pow(u, 1.15))
		var thick: float = lerpf(SHOT_TRAIL_THICK * 0.35, SHOT_TRAIL_THICK, pow(u, 0.85))
		var x0: float = -SHOT_TRAIL_LEN + float(si) * seg_w
		var back_mid: float = -(x0 + seg_w * 0.5)  # 该段距彗星头的距离
		var glow := ColorRect.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.visible = false
		glow.color = Color(core_col.r, core_col.g, core_col.b, alpha * 0.55)
		glow.position = Vector2(x0, -(thick * 0.5 + SHOT_GLOW_PAD * lerpf(0.35, 1.0, u)))
		glow.size = Vector2(seg_w + 1.0, thick + SHOT_GLOW_PAD * lerpf(0.7, 1.8, u))
		host.add_child(glow)
		trail_parts.append({"node": glow, "back": back_mid})
		for oi in n_out:
			var pad: float = float(n_out - oi) * SHOT_OUTLINE_PAD * lerpf(0.45, 1.0, u)
			var oc: Color = outline_cols[oi]
			var edge := ColorRect.new()
			edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			edge.visible = false
			edge.color = Color(oc.r, oc.g, oc.b, alpha * 0.85)
			edge.position = Vector2(x0, -(thick * 0.5 + pad))
			edge.size = Vector2(seg_w + 1.0, thick + pad * 2.0)
			host.add_child(edge)
			trail_parts.append({"node": edge, "back": back_mid})
		var core := ColorRect.new()
		core.mouse_filter = Control.MOUSE_FILTER_IGNORE
		core.visible = false
		core.color = Color(core_col.r, core_col.g, core_col.b, alpha)
		core.position = Vector2(x0, -thick * 0.5)
		core.size = Vector2(seg_w + 1.0, thick)
		host.add_child(core)
		trail_parts.append({"node": core, "back": back_mid})
	# 圆亮彗星头（始终在玩家/飞行尖端）
	var head_glow := _make_shot_orb(
		SHOT_HEAD_GLOW,
		Color(mini(core_col.r + 0.35, 1.0), mini(core_col.g + 0.35, 1.0), mini(core_col.b + 0.35, 1.0), 0.55)
	)
	host.add_child(head_glow)
	for oi in n_out:
		var oc2: Color = outline_cols[oi]
		var ring_sz: float = SHOT_HEAD_SIZE + float(n_out - oi) * SHOT_OUTLINE_PAD * 2.2
		var ring := _make_shot_orb(ring_sz, Color(oc2.r, oc2.g, oc2.b, 0.95))
		host.add_child(ring)
	var head_core := _make_shot_orb(
		SHOT_HEAD_SIZE,
		Color(mini(core_col.r + 0.45, 1.0), mini(core_col.g + 0.45, 1.0), mini(core_col.b + 0.45, 1.0), 1.0)
	)
	host.add_child(head_core)
	var head_hot := _make_shot_orb(
		SHOT_HEAD_SIZE * 0.45,
		Color(1.0, 1.0, 1.0, 0.95)
	)
	host.add_child(head_hot)
	var ctx := {
		"host": host,
		"from": from_g,
		"to": to_g,
		"waypoints": waypoints,
		"fired": {},
		"trail_parts": trail_parts,
	}
	_shot_projectile_step(0.0, ctx)
	var tw := create_tween()
	tw.tween_method(_shot_projectile_step.bind(ctx), 0.0, 1.0, maxf(travel_sec, 0.05)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	var fired: Dictionary = ctx.get("fired", {})
	for wi in waypoints.size():
		if fired.has(wi):
			continue
		var wp2: Dictionary = waypoints[wi]
		var amt2: int = 0
		var hi2: int = int(wp2.get("hit_index", -1))
		if hi2 >= 0 and state != null and state.has_paced_shot_pending():
			amt2 = state.resolve_paced_hit(hi2)
		else:
			amt2 = int(wp2.get("amount", 0))
		if amt2 > 0:
			_spawn_blood_burst(wp2.get("g", to_g), amt2)
	if is_instance_valid(host):
		host.queue_free()


func _make_shot_orb(diameter: float, col: Color) -> Panel:
	## 圆形彗星头/辉光（StyleBox 圆角=半径）。
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = Vector2(diameter, diameter)
	p.position = Vector2(-diameter * 0.5, -diameter * 0.5)
	var st := StyleBoxFlat.new()
	st.bg_color = col
	st.set_corner_radius_all(int(ceilf(diameter * 0.5)))
	st.set_border_width_all(0)
	p.add_theme_stylebox_override("panel", st)
	return p


func _shot_projectile_step(t: float, ctx: Dictionary) -> void:
	var host: Control = ctx.get("host") as Control
	if host == null or not is_instance_valid(host):
		return
	var from_g: Vector2 = ctx.get("from", Vector2.ZERO)
	var to_g: Vector2 = ctx.get("to", Vector2.ZERO)
	host.global_position = from_g.lerp(to_g, t)
	# 只显示「已经飞过」的拖尾：未飞出的尾巴不画，避免从屏幕左侧穿过玩家
	var traveled: float = from_g.distance_to(host.global_position)
	for item in ctx.get("trail_parts", []):
		var node: CanvasItem = item.get("node") as CanvasItem
		if node == null or not is_instance_valid(node):
			continue
		var back: float = float(item.get("back", 0.0))
		node.visible = back <= traveled + 6.0
	var waypoints: Array = ctx.get("waypoints", [])
	var fired: Dictionary = ctx.get("fired", {})
	var path_len: float = maxf(from_g.distance_to(to_g), 1.0)
	for wi in waypoints.size():
		if fired.has(wi):
			continue
		var wp: Dictionary = waypoints[wi]
		var wg: Vector2 = wp.get("g", Vector2.ZERO)
		var wt: float = from_g.distance_to(wg) / path_len
		if t + 0.02 >= wt:
			fired[wi] = true
			var amt: int = 0
			var hi: int = int(wp.get("hit_index", -1))
			if hi >= 0 and state != null and state.has_paced_shot_pending():
				# 视觉命中瞬间结算伤害（飘字由 enemy_damaged 触发）
				amt = state.resolve_paced_hit(hi)
			else:
				amt = int(wp.get("amount", 0))
			if amt > 0:
				_spawn_blood_burst(wg, amt)


func _spawn_blood_burst(at_g: Vector2, amount: int) -> void:
	## 命中飙血：带拖尾的线段轨迹（非抛物线血滴）；伤害越高条数越多、越长。
	if amount <= 0:
		return
	var t: float = clampf(float(amount) / 12.0, 0.0, 1.0)
	var n: int = int(round(lerpf(float(BLOOD_BURST_MIN), float(BLOOD_BURST_MAX), t)))
	for _i in n:
		var ang: float = randf_range(-PI * 0.85, PI * 0.85)
		# 略偏右飞出（射击方向），夹杂上下散开
		if randf() < 0.55:
			ang = randf_range(-0.55, 0.55)
		var dir := Vector2(cos(ang), sin(ang))
		var streak_len: float = lerpf(BLOOD_STREAK_LEN_MIN, BLOOD_STREAK_LEN_MAX, t) * randf_range(0.75, 1.2)
		var thick0: float = lerpf(2.2, 4.6, t) * randf_range(0.85, 1.15)
		var speed: float = lerpf(220.0, 420.0, t) * randf_range(0.85, 1.2)
		var dur: float = randf_range(0.22, 0.38)
		var origin: Vector2 = at_g + Vector2(randf_range(-4.0, 4.0), randf_range(-5.0, 5.0))
		var segs: Array = []
		var seg_w: float = streak_len / float(BLOOD_STREAK_SEGS)
		for si in BLOOD_STREAK_SEGS:
			var u: float = float(si) / float(maxi(BLOOD_STREAK_SEGS - 1, 1))  # 0=尾 1=头
			var rect := ColorRect.new()
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.z_index = 49
			var thick: float = thick0 * lerpf(0.25, 1.0, pow(u, 0.8))
			rect.size = Vector2(seg_w + 1.0, thick)
			var a: float = lerpf(0.15, 0.95, pow(u, 0.7))
			rect.color = Color(randf_range(0.78, 1.0), randf_range(0.04, 0.18), randf_range(0.04, 0.16), a)
			rect.pivot_offset = Vector2(0.0, thick * 0.5)
			rect.rotation = dir.angle()
			add_child(rect)
			segs.append(rect)
		var bctx := {
			"segs": segs,
			"origin": origin,
			"dir": dir,
			"speed": speed,
			"streak_len": streak_len,
			"seg_w": seg_w,
		}
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_method(_blood_streak_step.bind(bctx), 0.0, dur, dur)
		for rect2 in segs:
			tw.tween_property(rect2, "modulate:a", 0.0, dur).set_delay(dur * 0.25)
		tw.chain().tween_callback(_blood_streak_cleanup.bind(segs))


func _blood_streak_step(elapsed: float, bctx: Dictionary) -> void:
	var segs: Array = bctx.get("segs", [])
	if segs.is_empty():
		return
	var origin: Vector2 = bctx.get("origin", Vector2.ZERO)
	var dir: Vector2 = bctx.get("dir", Vector2.RIGHT)
	var speed: float = float(bctx.get("speed", 300.0))
	var streak_len: float = float(bctx.get("streak_len", 40.0))
	var seg_w: float = float(bctx.get("seg_w", 4.0))
	var head: Vector2 = origin + dir * (speed * elapsed)
	# 头在前，尾在后；按段贴在头→尾方向上
	for si in segs.size():
		var rect: ColorRect = segs[si] as ColorRect
		if rect == null or not is_instance_valid(rect):
			continue
		var u: float = float(si) / float(maxi(segs.size() - 1, 1))
		var along: float = -streak_len + float(si) * seg_w
		var p: Vector2 = head + dir * along
		rect.global_position = p - Vector2(0.0, rect.size.y * 0.5)


func _blood_streak_cleanup(segs: Array) -> void:
	for rect in segs:
		if rect != null and is_instance_valid(rect):
			rect.queue_free()


## 在正上击发点（红圈下）打出发黄闪；chamber 在盘上此时应对准正上。
func _flash_fire_at_top(slot_i: int) -> void:
	if _fire_flash_tween != null and _fire_flash_tween.is_valid():
		_fire_flash_tween.kill()
	_fire_flash_tween = create_tween()
	_fire_flash_tween.set_parallel(true)
	# 固定红圈脉冲：保证黄闪出现在正上击发点
	if _fire_ring != null and is_instance_valid(_fire_ring):
		_fire_ring.modulate = Color(1.8, 1.55, 0.35)
		_fire_flash_tween.tween_property(_fire_ring, "modulate", Color.WHITE, 0.32)
	# 当前对准正上的小圆一并发黄
	if slot_i >= 0 and slot_i < _chamber_panels.size():
		var panel: Panel = _chamber_panels[slot_i]
		panel.modulate = Color(1.7, 1.45, 0.55)
		_fire_flash_tween.tween_property(panel, "modulate", Color.WHITE, 0.32)


func _flash_fire_chamber_at(slot_i: int) -> void:
	_flash_fire_at_top(slot_i)


func _on_roll() -> void:
	if _busy():
		return
	if not state.can_start_roll():
		return
	_rolling = true
	_refresh_hud_only()
	# 与装填满匣后的随机转同一套路径；转完后结束玩家行动（怪前进）
	var steps: int = await _run_shared_cylinder_spin()
	if steps < 0:
		_rolling = false
		_refresh()
		return
	state.resolve_after_player_action()
	_rolling = false
	_refresh()


## 装填满匣后 spin 与 ROLL 按钮共用：先对齐视觉到当前 start，再 apply_roll，再整圈动画落点。
## 返回 apply_roll 步数（失败 -1；单发可为 0）。
func _run_shared_cylinder_spin() -> int:
	if not state.can_start_roll():
		return -1
	# 先把盘面钉在当前逻辑锤位，避免视觉步数漂移导致「看起来没转 / 落点错」
	_apply_disk_rotation(float(state.magazine.start_index))
	_refresh_mag_contents()
	var steps: int = state.apply_roll()
	if steps < 0:
		return -1
	if steps > 0:
		await _play_roll_spin_visual(steps)
	else:
		_apply_disk_rotation(float(state.magazine.start_index))
	return steps


## 大盘随机转：逻辑步数 + 至少一整圈，落点仍对齐 start_index；红圈不动。
func _play_roll_spin_visual(logic_steps: int) -> void:
	var extra: int = CombatConstants.MAGAZINE_SIZE * ROLL_VISUAL_EXTRA_TURNS
	var visual: float = float(logic_steps + extra)
	var dur: float = _paced(clampf(
		ROLL_ANIM_BASE + visual * ROLL_ANIM_PER_STEP,
		ROLL_ANIM_BASE,
		ROLL_ANIM_MAX
	))
	await _animate_disk_to(_wheel_visual_steps + visual, dur)


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
	elif state.needs_endless_shop():
		_open_endless_shop()
	else:
		_on_next_wave()


func _return_to_map(victory: bool) -> void:
	if victory and not state.can_start_next_wave():
		return
	var payload := state.export_run_payload()
	RunState.apply_combat_result(payload, victory)
	get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_next_wave() -> void:
	if _busy() or _shop_open:
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


func _toggle_dev() -> void:
	if (not _dev_open) and (_reward_open or _shop_open):
		return
	_dev_open = not _dev_open
	dev_panel.visible = _dev_open
	if _dev_open:
		_hide_ammo_detail()
		_hide_muzzle_tip()
	_update_dimmer()


func _update_dimmer() -> void:
	# 悬停/长按弹药详情不盖遮罩；开发面板 / 奖励 / 无限商店 / 罪孽选择用遮罩
	dimmer.visible = _dev_open or _reward_open or _shop_open or _sin_pick_open


func _set_reward_open(open: bool) -> void:
	_reward_open = open
	reward_panel.visible = open
	if open:
		_dev_open = false
		dev_panel.visible = false
		_hide_ammo_detail()
		_hide_muzzle_tip()
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
			btn.custom_minimum_size = Vector2(0, 72)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var nm := str(def.get("name", "未知#%d" % ammo_id))
			var desc := str(def.get("special", ""))
			var blurb := DataRegistry.format_ammo_reward_blurb(ammo_id)
			btn.text = "【%d】%s\n%s" % [i + 1, nm, blurb]
			if not desc.is_empty():
				btn.tooltip_text = desc
			btn.add_theme_font_size_override("font_size", 18)
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
			if state.endless_mode and state.needs_endless_shop():
				reward_hint.text = "第 %d 波已清：请先进入商店（每 5 波一次），逛完后再开下一波。牌库跨波保留。" % state.wave_index
				btn_reward_next.text = "进入商店 SHOP"
			elif state.endless_mode:
				reward_hint.text = "可继续下一波（无限模式：牌库与奖励弹药跨波保留）。无伤/三回合额外金灰盒暂未结算。"
				btn_reward_next.text = "下一波 NEXT"
			else:
				reward_hint.text = "可继续下一波（练习战胜利后弹药已重置为开局牌库）。练习战无地图。无伤/三回合额外金灰盒暂未结算。"
				btn_reward_next.text = "下一波 NEXT"
		btn_reward_skip.visible = false
		btn_reward_next.visible = true
		if state.needs_endless_shop():
			btn_reward_next.disabled = false
		else:
			btn_reward_next.disabled = not state.can_start_next_wave()
	else:
		reward_hint.text = ""
		btn_reward_skip.visible = false
		btn_reward_next.visible = false



func _on_enemy_damaged(cell: int, amount: int, kind: String = "") -> void:
	if _defer_hit_vfx:
		_pending_hit_vfx.append({"cell": cell, "amount": amount, "kind": kind})
		return
	_spawn_damage_float(cell, amount, kind)


func _on_player_damaged(amount: int, kind: String = "") -> void:
	## 只抖玩家单位块（格 0），与怪物受击同套振幅；飘字挂玩家格。
	_spawn_damage_float(CombatConstants.PLAYER_CELL, amount, kind)


func _on_gold_gained(cell: int, amount: int) -> void:
	## 贪婪掉金：金色 +N，动画与伤害飘字相同。
	_spawn_damage_float(cell, amount, "金币")


func _spawn_damage_float(cell: int, amount: int, kind: String = "") -> void:
	## 从敌人格弹出 -N；状态伤（流血/燃烧/导电/汽油）带状态名。二次贝塞尔弧线上升并淡出。
	if amount <= 0 or board_row == null:
		return
	if cell < 0 or cell >= board_row.get_child_count():
		return
	var panel: Control = board_row.get_child(cell) as Control
	if panel == null:
		return
	var anchor: Control = panel.get_node_or_null("UnitBody") as Control
	if anchor == null or not anchor.visible:
		anchor = panel
	var start_g: Vector2 = anchor.get_global_rect().get_center()
	start_g.x += randf_range(-28.0, 28.0)
	start_g.y += randf_range(-18.0, 10.0)
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.z_index = 42
	if kind == "金币":
		lab.text = "+%d" % amount
	elif kind == "":
		lab.text = "-%d" % amount
	else:
		lab.text = "%s\n-%d" % [kind, amount]
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font_sz: int = _float_font_size_for(amount, kind != "" and kind != "金币")
	lab.add_theme_font_size_override("font_size", font_sz)
	var col := Color(1.0, 0.42, 0.22)
	match kind:
		"流血":
			col = Color(0.95, 0.2, 0.28)
		"燃烧":
			col = Color(1.0, 0.55, 0.15)
		"导电":
			col = Color(0.95, 0.9, 0.25)
		"汽油":
			col = Color(0.75, 0.95, 0.35)
		"金币":
			col = Color(1.0, 0.84, 0.25)
	lab.add_theme_color_override("font_color", col)
	if kind != "金币":
		_shake_cell_for_damage(cell, amount)
	lab.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.02, 0.95))
	lab.add_theme_constant_override("outline_size", 5)
	lab.modulate = Color(1, 1, 1, 1)
	add_child(lab)
	lab.reset_size()
	var half := lab.size * 0.5
	if half.x < 1.0:
		half = Vector2(18, 12)
	lab.global_position = start_g - half
	var drift_x := randf_range(-64.0, 64.0)
	if absf(drift_x) < 18.0:
		drift_x = 22.0 if randf() > 0.5 else -22.0
	var ctrl := start_g + Vector2(drift_x * 0.55, -DMG_FLOAT_RISE * 0.55)
	var end_g := start_g + Vector2(drift_x, -DMG_FLOAT_RISE)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(_damage_float_step.bind(lab, start_g, ctrl, end_g), 0.0, 1.0, DMG_FLOAT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 0.0, DMG_FLOAT_DURATION).set_delay(0.2)
	tw.chain().tween_callback(lab.queue_free)


func _float_font_size_for(amount: int, has_kind_label: bool) -> int:
	## 飘字字号随数值放大；带状态名时略小一档以免换行撑爆。
	var a: float = float(maxi(amount, 1))
	var t: float = clampf((a - 1.0) / 24.0, 0.0, 1.0)
	var base: int = int(round(lerpf(float(DMG_FLOAT_FONT_MIN), float(DMG_FLOAT_FONT_MAX), t)))
	if has_kind_label:
		base = maxi(DMG_FLOAT_FONT_MIN, base - 4)
	return base


func _shake_cell_body(panel: Control) -> Control:
	## 抖单位占位块 UnitBody（不抖整块棋盘/地块）。
	var body: Control = panel.get_node_or_null("UnitBody") as Control
	if body == null:
		body = panel.get_node_or_null("VBox") as Control
	if body == null:
		body = panel
	return body


func _reset_cell_shake_offsets(body: Control) -> void:
	## 抖完必须回到贴地休息位；勿清 offset_*（会把无锚点 Panel 甩到 0,0）。
	if not is_instance_valid(body):
		return
	body.position = _unit_rest_position()


func _shake_cell_for_damage(cell: int, amount: int) -> void:
	## 仅被击中的单位块抖动（怪或玩家）；振幅随伤害放大（小伤也明显）。不抖整盘。
	if board_row == null or amount <= 0:
		return
	if cell < 0 or cell >= board_row.get_child_count():
		return
	var panel: Control = board_row.get_child(cell) as Control
	if panel == null:
		return
	var body: Control = _shake_cell_body(panel)
	# 伤害曲线：小伤也有下限可见度，约 12 伤即接近最大
	var t: float = clampf(0.22 + float(amount) / 14.0, 0.22, 1.0)
	var amp: float = lerpf(SHAKE_MIN_PX, SHAKE_MAX_PX, t)
	if _cell_shake_tweens.has(cell):
		var old_tw: Tween = _cell_shake_tweens[cell] as Tween
		if old_tw != null:
			old_tw.kill()
	_reset_cell_shake_offsets(body)
	var tw := create_tween()
	_cell_shake_tweens[cell] = tw
	tw.finished.connect(func():
		_cell_shake_tweens.erase(cell)
		_reset_cell_shake_offsets(body)
	)
	var steps := 7
	for i in steps:
		var fall: float = 1.0 - float(i) / float(steps)
		var ox := randf_range(-amp, amp) * fall
		# 纵向振幅收一点，且不把底边抖到地面线以下太多
		var oy := randf_range(-amp * 0.45, amp * 0.25) * fall
		tw.tween_callback(_apply_cell_offsets.bind(body, ox, oy))
		tw.tween_interval(SHAKE_DURATION / float(steps))
	tw.tween_callback(_reset_cell_shake_offsets.bind(body))


func _apply_cell_offsets(body: Control, ox: float, oy: float) -> void:
	if not is_instance_valid(body):
		return
	body.position = _unit_rest_position() + Vector2(ox, oy)


func _damage_float_step(t: float, lab: Label, start_g: Vector2, ctrl: Vector2, end_g: Vector2) -> void:
	if not is_instance_valid(lab):
		return
	var u := 1.0 - t
	var p := u * u * start_g + 2.0 * u * t * ctrl + t * t * end_g
	var h := lab.size * 0.5
	if h.x < 1.0:
		h = Vector2(18, 12)
	lab.global_position = p - h


func _build_endless_shop_panel() -> void:
	if _shop_panel != null:
		return
	_shop_panel = PanelContainer.new()
	_shop_panel.name = "EndlessShopPanel"
	_shop_panel.visible = false
	_shop_panel.z_index = 12
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	_shop_panel.offset_left = -380.0
	_shop_panel.offset_top = -300.0
	_shop_panel.offset_right = 380.0
	_shop_panel.offset_bottom = 300.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.16, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.92, 0.72, 0.35, 0.95)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_shop_panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	_shop_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	_shop_title = Label.new()
	_shop_title.text = "无限商店 · 灰盒"
	_shop_title.add_theme_font_size_override("font_size", 22)
	_shop_title.add_theme_color_override("font_color", COL_REWARD_TITLE)
	root.add_child(_shop_title)
	_shop_gold_label = Label.new()
	_shop_gold_label.add_theme_color_override("font_color", COL_GOLD)
	root.add_child(_shop_gold_label)
	_shop_hint = Label.new()
	_shop_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_hint.add_theme_color_override("font_color", COL_REWARD_HINT)
	root.add_child(_shop_hint)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	var stock_title := Label.new()
	stock_title.text = "库存"
	left.add_child(stock_title)
	var stock_scroll := ScrollContainer.new()
	stock_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stock_scroll.custom_minimum_size = Vector2(0, 220)
	left.add_child(stock_scroll)
	_shop_stock = VBoxContainer.new()
	_shop_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_scroll.add_child(_shop_stock)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	var bag_title := Label.new()
	bag_title.text = "袋内可删"
	right.add_child(bag_title)
	var bag_scroll := ScrollContainer.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_scroll.custom_minimum_size = Vector2(0, 220)
	right.add_child(bag_scroll)
	_shop_bag_list = VBoxContainer.new()
	_shop_bag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(_shop_bag_list)
	_shop_msg = Label.new()
	_shop_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_msg.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	root.add_child(_shop_msg)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)
	_btn_shop_reroll = Button.new()
	_btn_shop_reroll.custom_minimum_size = Vector2(220, 40)
	_btn_shop_reroll.pressed.connect(_on_endless_shop_reroll)
	_style_reward_action_button(_btn_shop_reroll)
	actions.add_child(_btn_shop_reroll)
	_btn_shop_leave = Button.new()
	_btn_shop_leave.text = "离开商店 · 可下一波"
	_btn_shop_leave.custom_minimum_size = Vector2(220, 40)
	_btn_shop_leave.pressed.connect(_on_endless_shop_leave)
	_style_reward_action_button(_btn_shop_leave)
	actions.add_child(_btn_shop_leave)
	add_child(_shop_panel)


func _open_endless_shop() -> void:
	if state == null or not state.needs_endless_shop():
		return
	if _shop_panel == null:
		_build_endless_shop_panel()
	_set_reward_open(false)
	_dev_open = false
	dev_panel.visible = false
	_hide_ammo_detail()
	var seed_v: int = state.wave_index * 9973 + state.gold * 13 + 17
	_shop.begin(state.gold, state.bag, state.wave_index, seed_v)
	_shop_open = true
	_shop_panel.visible = true
	_refresh_endless_shop_panel()
	_update_dimmer()


func _refresh_endless_shop_panel() -> void:
	if _shop_panel == null or not _shop.open:
		return
	_shop_title.text = "无限商店 · 第 %d 波后" % state.wave_index
	_shop_gold_label.text = "金币 %d" % _shop.gold
	_shop_hint.text = "购买：单价 %d 金/发。重随：免费 %d 次，之后每次 %d 金。移除：本店递增（%d、再 +%d…），离店重置。逛完后才可下一波。" % [
		ShopConstants.AMMO_PRICE,
		ShopConstants.FREE_REROLLS,
		ShopConstants.REROLL_COST,
		ShopConstants.REMOVE_BASE_COST,
		ShopConstants.REMOVE_COST_STEP,
	]
	var rc: int = _shop.reroll_cost_now()
	if rc <= 0:
		_btn_shop_reroll.text = "重随库存（免费剩余 %d）" % _shop.free_rerolls_left
	else:
		_btn_shop_reroll.text = "重随库存（%d 金）" % rc
	_btn_shop_reroll.disabled = not _shop.can_reroll()
	_shop_msg.text = _shop.last_message
	_refresh_endless_shop_stock()
	_refresh_endless_shop_bag()


func _refresh_endless_shop_stock() -> void:
	for c in _shop_stock.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "库存（随机 · 无稀有度权重）"
	_shop_stock.add_child(title)
	for i in _shop.stock.size():
		var ammo_id: int = _shop.stock[i]
		var def: Dictionary = DataRegistry.get_ammo(ammo_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := Label.new()
		var price: int = _shop.ammo_price(ammo_id)
		if _shop.sold[i]:
			info.text = "%s · 已售出" % str(def.get("name", ammo_id))
			info.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		else:
			info.text = "%s · %d 金" % [str(def.get("name", ammo_id)), price]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var btn := Button.new()
		btn.text = "购买"
		btn.custom_minimum_size = Vector2(88, 36)
		btn.disabled = not _shop.can_buy(i)
		var idx := i
		btn.pressed.connect(func(): _on_endless_shop_buy(idx))
		row.add_child(btn)
		_shop_stock.add_child(row)


func _refresh_endless_shop_bag() -> void:
	for c in _shop_bag_list.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "袋内可删（下次移除 %d 金 · 本店已删 %d 次）· 共 %d 发" % [
		_shop.next_remove_cost(), _shop.removes_done, _shop.bag.size()
	]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_bag_list.add_child(title)
	if _shop.bag.is_empty():
		var empty := Label.new()
		empty.text = "（空）"
		_shop_bag_list.add_child(empty)
		return
	var counts: Dictionary = {}
	var order: Array = []
	for ammo_id in _shop.bag:
		var idv: int = int(ammo_id)
		if not counts.has(idv):
			order.append(idv)
			counts[idv] = 0
		counts[idv] = int(counts[idv]) + 1
	for ammo_id in order:
		var def: Dictionary = DataRegistry.get_ammo(int(ammo_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.text = "%s ×%d" % [str(def.get("name", ammo_id)), int(counts[ammo_id])]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var btn := Button.new()
		btn.text = "移除 %d 金" % _shop.next_remove_cost()
		btn.custom_minimum_size = Vector2(120, 36)
		var aid: int = int(ammo_id)
		btn.disabled = _shop.gold < _shop.next_remove_cost()
		btn.pressed.connect(func(): _on_endless_shop_remove(aid))
		row.add_child(btn)
		_shop_bag_list.add_child(row)


func _on_endless_shop_buy(slot: int) -> void:
	if _shop.buy(slot):
		_refresh_endless_shop_panel()


func _on_endless_shop_remove(ammo_id: int) -> void:
	var idx := _shop.bag.find(ammo_id)
	if idx < 0:
		return
	if _shop.remove_at(idx):
		_refresh_endless_shop_panel()


func _on_endless_shop_reroll() -> void:
	if _shop.reroll():
		_refresh_endless_shop_panel()


func _on_endless_shop_leave() -> void:
	if not _shop.open:
		return
	var payload: Dictionary = _shop.end_session()
	state.apply_shop_payload(payload)
	state.mark_endless_shop_done()
	_shop_open = false
	if _shop_panel != null:
		_shop_panel.visible = false
	_update_dimmer()
	# 离店后重新打开奖励面板，方便点「下一波」
	if state.phase == CombatState.Phase.WON and state.reward_resolved:
		_set_reward_open(true)
	_refresh()


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
		if state.needs_endless_shop():
			_open_endless_shop()


func _on_reward_skip() -> void:
	if state.skip_reward_for_gold():
		_refresh_reward_panel()
		if state.needs_endless_shop():
			_open_endless_shop()


func _bag_inventory_fingerprint(inv: Dictionary) -> String:
	var keys: Array = inv.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k in keys:
		var e: Dictionary = inv[k]
		parts.append("%s:%s/%s/%s" % [
			str(k), str(e.get("bag", 0)), str(e.get("mag", 0)), str(e.get("discard", 0))
		])
	return "%s|g%d|t%d" % ["|".join(parts), state.gold, state.count_temporary_in_bag()]


func _refresh_bag_list() -> void:
	var inv: Dictionary = state.ammo_inventory_by_id()
	var fp := _bag_inventory_fingerprint(inv)
	var bag_n: int = state.bag.size()
	var mag_n: int = state.magazine.loaded_count() if state.magazine != null else 0
	var disc_n: int = state.discard.size()
	var total_n: int = bag_n + mag_n + disc_n
	if bag_header_label != null:
		bag_header_label.text = "弹药盒 · 袋%d" % bag_n
	# 结构只建一次：统计 + 物理盒 + 提示
	if _bag_physics == null or not is_instance_valid(_bag_physics):
		_bag_refreshing = true
		for c in bag_list.get_children():
			c.queue_free()
		var title := Label.new()
		title.name = "BagStatsLabel"
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 12)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bag_list.add_child(title)
		_bag_physics = BagPhysicsBox.new()
		_bag_physics.name = "BagPhysicsBox"
		_bag_physics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bag_physics.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_bag_physics.custom_minimum_size = Vector2(200, 210)
		_bag_physics.color_lookup = Callable(self, "_ammo_colors")
		_bag_physics.name_lookup = Callable(self, "_ammo_bag_glyph")
		_bag_physics.ball_hover.connect(_on_bag_physics_hover)
		_bag_physics.ball_hover_exit.connect(_on_bag_physics_hover_exit)
		_bag_physics.ball_press.connect(_on_bag_physics_press)
		bag_list.add_child(_bag_physics)
		var tip := Label.new()
		tip.name = "BagTipLabel"
		tip.text = "袋内重力球 · 悬停/长按看效果"
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.add_theme_font_size_override("font_size", 11)
		tip.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bag_list.add_child(tip)
		_bag_refreshing = false
	var stats: Label = bag_list.get_node_or_null("BagStatsLabel") as Label
	if stats != null:
		stats.text = "共%d · 袋%d · 膛%d · 弃%d · 金%d" % [
			total_n, bag_n, mag_n, disc_n, state.gold
		]
	if fp == _bag_inv_fingerprint and _bag_physics != null and _bag_physics.ball_count() == bag_n:
		return
	_bag_inv_fingerprint = fp
	# 物理盒只同步「袋」内每发；膛/弃仍在统计行可见
	var ids: Array = []
	var temps: Array = []
	for i in state.bag.size():
		ids.append(int(state.bag[i]))
		temps.append(state.is_bag_index_temporary(i))
	_bag_physics.sync_ammo_ids(ids, temps)
	if _detail_open and _hover_ammo_id >= 0:
		_show_ammo_detail(_hover_ammo_id, _bag_physics, true, false)


func _ammo_bag_glyph(ammo_id: int) -> String:
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		return "无"
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	var full_name: String = str(def.get("name", "#%d" % ammo_id))
	var short := full_name.replace("子弹", "").replace("弹药", "")
	if short.is_empty():
		return str(ammo_id)
	return short.substr(0, 1)


func _on_bag_physics_hover(ammo_id: int) -> void:
	_hover_ammo_id = ammo_id
	_show_ammo_detail(ammo_id, _bag_physics, true, false)


func _on_bag_physics_hover_exit(ammo_id: int) -> void:
	if _bag_refreshing:
		return
	if _hover_ammo_id == ammo_id:
		_hover_ammo_id = -1
	if _detail_from_hover and not _detail_from_long_press and _detail_ammo_id == ammo_id:
		_hide_ammo_detail()


func _on_bag_physics_press(ammo_id: int) -> void:
	# 触屏/点击：走长按计时；桌面点击也弹出详情
	_begin_long_press(ammo_id, _bag_physics)
	_show_ammo_detail(ammo_id, _bag_physics, true, false)


func _on_bag_cell_hover_enter(ammo_id: int, cell: Control) -> void:
	_hover_ammo_id = ammo_id
	_show_ammo_detail(ammo_id, cell, true, false)


func _on_bag_cell_hover_exit(ammo_id: int) -> void:
	if _bag_refreshing:
		return
	if _hover_ammo_id == ammo_id:
		_hover_ammo_id = -1
	if _detail_from_hover and not _detail_from_long_press and _detail_ammo_id == ammo_id:
		_hide_ammo_detail()


func _on_bag_cell_input(event: InputEvent, ammo_id: int, cell: Control) -> void:
	# 触屏长按：按下开始计时，抬起结束；桌面仍以悬停为主
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_begin_long_press(ammo_id, cell)
		else:
			_cancel_long_press(true)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		# 仅在触控仿真 / 无悬停设备时用按住当长按；普通鼠标点击不钉住
		if mb.pressed:
			if DisplayServer.is_touchscreen_available() and _hover_ammo_id < 0:
				_begin_long_press(ammo_id, cell)
		else:
			if _detail_from_long_press:
				_cancel_long_press(true)


func _begin_long_press(ammo_id: int, cell: Control) -> void:
	_ensure_long_press_timer()
	_long_press_kind = "ammo"
	_long_press_ammo_id = ammo_id
	_long_press_timer.stop()
	_long_press_timer.start(LONG_PRESS_SEC)
	# 记下锚定控件，timeout 时再弹
	_long_press_timer.set_meta("cell", cell)


func _cancel_long_press(hide_if_long: bool) -> void:
	if _long_press_timer != null:
		_long_press_timer.stop()
	_long_press_ammo_id = -1
	if hide_if_long and _detail_from_long_press:
		_hide_ammo_detail()


func _on_long_press_timeout() -> void:
	if _long_press_kind == "muzzle":
		_show_muzzle_tip(false, true)
		return
	var ammo_id := _long_press_ammo_id
	if ammo_id < 0:
		return
	var cell: Control = null
	if _long_press_timer != null and _long_press_timer.has_meta("cell"):
		cell = _long_press_timer.get_meta("cell")
	_show_ammo_detail(ammo_id, cell, false, true)


func _build_ammo_detail_panel() -> void:
	_ammo_detail_panel = PanelContainer.new()
	_ammo_detail_panel.name = "AmmoDetailPanel"
	_ammo_detail_panel.visible = false
	_ammo_detail_panel.z_index = 14
	_ammo_detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_detail_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ammo_detail_panel.offset_left = 0.0
	_ammo_detail_panel.offset_top = 0.0
	_ammo_detail_panel.offset_right = DETAIL_PANEL_W
	_ammo_detail_panel.offset_bottom = DETAIL_PANEL_H
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.09, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(0.95, 0.78, 0.4, 0.95)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_ammo_detail_panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_ammo_detail_title = Label.new()
	_ammo_detail_title.name = "DetailTitle"
	_ammo_detail_title.text = "弹药详情"
	_ammo_detail_title.add_theme_font_size_override("font_size", 20)
	_ammo_detail_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_ammo_detail_body = RichTextLabel.new()
	_ammo_detail_body.name = "DetailBody"
	_ammo_detail_body.bbcode_enabled = false
	_ammo_detail_body.fit_content = false
	_ammo_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ammo_detail_body.custom_minimum_size = Vector2(0, 240)
	_ammo_detail_body.add_theme_font_size_override("normal_font_size", 15)
	_ammo_detail_body.add_theme_color_override("default_color", Color(0.96, 0.94, 0.88))
	vbox.add_child(_ammo_detail_title)
	vbox.add_child(_ammo_detail_body)
	_ammo_detail_panel.add_child(vbox)
	add_child(_ammo_detail_panel)


func _build_muzzle_tip_panel() -> void:
	if _muzzle_tip_panel != null:
		return
	_muzzle_tip_panel = PanelContainer.new()
	_muzzle_tip_panel.name = "MuzzleTipPanel"
	_muzzle_tip_panel.visible = false
	_muzzle_tip_panel.z_index = 15
	_muzzle_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_muzzle_tip_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.7, 0.3, 0.95)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_muzzle_tip_panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "枪口伤害修正"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_muzzle_tip_body = RichTextLabel.new()
	_muzzle_tip_body.name = "MuzzleTipBody"
	_muzzle_tip_body.bbcode_enabled = false
	_muzzle_tip_body.fit_content = true
	_muzzle_tip_body.scroll_active = false
	_muzzle_tip_body.custom_minimum_size = Vector2(300, 0)
	_muzzle_tip_body.add_theme_font_size_override("normal_font_size", 15)
	_muzzle_tip_body.add_theme_color_override("default_color", Color(0.96, 0.94, 0.88))
	vbox.add_child(title)
	vbox.add_child(_muzzle_tip_body)
	_muzzle_tip_panel.add_child(vbox)
	add_child(_muzzle_tip_panel)


func _refresh_muzzle_tip_body() -> void:
	if _muzzle_tip_body == null or state == null:
		return
	_muzzle_tip_body.text = state.muzzle_damage_tip_text()


func _position_muzzle_tip() -> void:
	if _muzzle_tip_panel == null or _muzzle_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var r := _muzzle_panel.get_global_rect()
	_muzzle_tip_panel.reset_size()
	var sz := _muzzle_tip_panel.size
	if sz.x < 10.0:
		sz = Vector2(320, 220)
	var pos := Vector2(r.position.x, r.end.y + 8.0)
	if pos.x + sz.x > vp.x - 8.0:
		pos.x = maxf(8.0, vp.x - sz.x - 8.0)
	if pos.y + sz.y > vp.y - 8.0:
		pos.y = maxf(8.0, r.position.y - sz.y - 8.0)
	_muzzle_tip_panel.global_position = pos


func _show_muzzle_tip(from_hover: bool = false, from_long_press: bool = false) -> void:
	if _muzzle_tip_panel == null or state == null or _reward_open or _shop_open or _sin_pick_open:
		return
	_hide_ammo_detail()
	_muzzle_tip_from_hover = from_hover
	_muzzle_tip_from_long_press = from_long_press
	_muzzle_tip_open = true
	_refresh_muzzle_tip_body()
	_muzzle_tip_panel.visible = true
	_position_muzzle_tip()


func _hide_muzzle_tip() -> void:
	_muzzle_tip_open = false
	_muzzle_tip_from_hover = false
	_muzzle_tip_from_long_press = false
	if _muzzle_tip_panel != null:
		_muzzle_tip_panel.visible = false


func _on_muzzle_hover_enter() -> void:
	_show_muzzle_tip(true, false)


func _on_muzzle_hover_exit() -> void:
	if _muzzle_tip_from_hover and not _muzzle_tip_from_long_press:
		_hide_muzzle_tip()


func _on_muzzle_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_muzzle_long_press()
			_show_muzzle_tip(true, false)
		else:
			_cancel_muzzle_long_press()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if DisplayServer.is_touchscreen_available():
				_begin_muzzle_long_press()
			_show_muzzle_tip(true, false)
		else:
			_cancel_muzzle_long_press()


func _begin_muzzle_long_press() -> void:
	_ensure_long_press_timer()
	_long_press_kind = "muzzle"
	_long_press_ammo_id = -1
	_long_press_timer.stop()
	_long_press_timer.start(LONG_PRESS_SEC)


func _cancel_muzzle_long_press() -> void:
	if _long_press_timer != null and _long_press_kind == "muzzle":
		_long_press_timer.stop()
	_long_press_kind = ""
	if _muzzle_tip_from_long_press:
		_hide_muzzle_tip()


func _hide_ammo_detail() -> void:
	_detail_open = false
	_detail_ammo_id = -1
	_detail_from_hover = false
	_detail_from_long_press = false
	if _ammo_detail_panel != null:
		_ammo_detail_panel.visible = false
	_update_dimmer()


func _position_ammo_detail_near(cell: Control) -> void:
	if _ammo_detail_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var pos := Vector2(24, 80)
	if cell != null and is_instance_valid(cell):
		pos = cell.get_global_rect().position + Vector2(-DETAIL_PANEL_W - 12, 0)
		if pos.x < 8:
			pos.x = cell.get_global_rect().end.x + 12
		if pos.y + DETAIL_PANEL_H > vp.y - 8:
			pos.y = maxf(8.0, vp.y - DETAIL_PANEL_H - 8.0)
		if pos.x + DETAIL_PANEL_W > vp.x - 8:
			pos.x = maxf(8.0, vp.x - DETAIL_PANEL_W - 8.0)
	_ammo_detail_panel.global_position = pos
	_ammo_detail_panel.size = Vector2(DETAIL_PANEL_W, DETAIL_PANEL_H)


func _show_ammo_detail(ammo_id: int, cell: Control = null, from_hover: bool = false, from_long_press: bool = false) -> void:
	if _ammo_detail_body == null or _reward_open:
		return
	_hide_muzzle_tip()
	_detail_ammo_id = ammo_id
	_detail_from_hover = from_hover
	_detail_from_long_press = from_long_press
	_detail_open = true
	var title_name := "弹药详情"
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		title_name = CombatConstants.INVALID_AMMO_NAME
	else:
		var def: Dictionary = DataRegistry.get_ammo(ammo_id)
		title_name = str(def.get("name", "弹药详情"))
	if _ammo_detail_title != null:
		_ammo_detail_title.text = title_name
	_ammo_detail_body.text = DataRegistry.format_ammo_detail_text(ammo_id)
	_ammo_detail_panel.visible = true
	_position_ammo_detail_near(cell)
	_update_dimmer()


func _build_sin_pick_panel() -> void:
	if _sin_panel != null:
		return
	_sin_panel = PanelContainer.new()
	_sin_panel.name = "SinPickPanel"
	_sin_panel.visible = false
	_sin_panel.z_index = 14
	_sin_panel.set_anchors_preset(Control.PRESET_CENTER)
	_sin_panel.offset_left = -320.0
	_sin_panel.offset_top = -220.0
	_sin_panel.offset_right = 320.0
	_sin_panel.offset_bottom = 220.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.14, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.55, 0.35, 0.95)
	style.set_corner_radius_all(12)
	_sin_panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_sin_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "选择你的罪孽"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = "开局弹药袋：平庸子弹 ×10 + 所选罪孽弹 ×5"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9))
	vbox.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	_sin_add_choice_btn(row, "愤怒", "伤3 · 枪口愤怒叠伤\n装≥3自伤6", FireResolver.ID_WRATH, Color(0.75, 0.18, 0.18))
	_sin_add_choice_btn(row, "傲慢", "伤2 · 枪口傲慢本场\n装≥3拉近敌人", FireResolver.ID_PRIDE, Color(0.55, 0.35, 0.85))
	_sin_add_choice_btn(row, "贪婪", "伤2 · 枪口贪婪掉金\n装≥3金币-6", FireResolver.ID_GREED, Color(0.2, 0.65, 0.35))
	add_child(_sin_panel)


func _sin_add_choice_btn(parent: Control, title: String, blurb: String, ammo_id: int, accent: Color) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 150)
	b.text = "%s\n%s" % [title, blurb]
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35, 0.95)
	sb.set_border_width_all(2)
	sb.border_color = accent
	sb.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", sb)
	var sb2 := sb.duplicate()
	sb2.bg_color = Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5, 0.98)
	b.add_theme_stylebox_override("hover", sb2)
	b.pressed.connect(func(id := ammo_id): _on_sin_picked(id))
	parent.add_child(b)


func _open_sin_pick() -> void:
	_sin_pick_open = true
	if _sin_panel != null:
		_sin_panel.visible = true
	_update_dimmer()


func _on_sin_picked(sin_ammo_id: int) -> void:
	_sin_pick_open = false
	if _sin_panel != null:
		_sin_panel.visible = false
	_update_dimmer()
	state.start_graybox(0, _pending_start_endless, sin_ammo_id)
	state.pace_after_fire = true
	_refresh()


func _wire_dev_buttons() -> void:
	%DevClose.pressed.connect(func(): _toggle_dev())
	_rebuild_dev_tool_body()
	# 加宽开发面板以容纳三列
	dev_panel.custom_minimum_size = Vector2(920, 520)
	dev_panel.set_anchors_preset(Control.PRESET_CENTER)
	dev_panel.offset_left = -460.0
	dev_panel.offset_top = -280.0
	dev_panel.offset_right = 460.0
	dev_panel.offset_bottom = 280.0


func _rebuild_dev_tool_body() -> void:
	## 三列：常规 | 弹药袋 | 敌人
	var inner: VBoxContainer = get_node_or_null("%DevInner") as VBoxContainer
	if inner == null and dev_panel != null:
		inner = dev_panel.get_node_or_null("DevMargin/DevVBox/DevScroll/DevInner") as VBoxContainer
	if inner == null:
		push_error("DevInner missing; skip rebuild_dev_tool_body")
		return
	for c in inner.get_children():
		inner.remove_child(c)
		c.free()
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	inner.add_child(cols)
	var col_general := _dev_make_column("常规")
	var col_ammo := _dev_make_column("弹药袋")
	var col_enemy := _dev_make_column("敌人")
	cols.add_child(col_general["root"])
	cols.add_child(col_ammo["root"])
	cols.add_child(col_enemy["root"])
	# —— 常规 ——
	_dev_add_btn(col_general["box"], "金币 +10", func(): state.dev_add_gold(10))
	_dev_add_btn(col_general["box"], "玩家 HP +5", func(): state.dev_set_player_hp(state.player_hp + 5))
	_dev_add_btn(col_general["box"], "玩家 HP -5", func(): state.dev_set_player_hp(state.player_hp - 5))
	_dev_add_btn(col_general["box"], "前敌 HP→1", func(): state.dev_set_front_enemy_hp(1))
	_dev_add_btn(col_general["box"], "强制装 6 白", func():
		var ids: Array[int] = [
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID
		]
		state.dev_force_load(ids)
	)
	_dev_add_btn(col_general["box"], "跳过怪回合", func(): state.dev_skip_enemy_turn())
	# —— 弹药 ——
	_dev_add_btn(col_ammo["box"], "清空弹药袋", func(): state.dev_clear_bag())
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		var aname: String = str(item.get("name", aid))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		col_ammo["box"].add_child(row)
		var lab := Label.new()
		lab.text = aname
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.clip_text = true
		row.add_child(lab)
		var b_add := Button.new()
		b_add.text = "+"
		b_add.custom_minimum_size = Vector2(36, 28)
		b_add.pressed.connect(func(id := aid): state.dev_add_ammo(id, 1))
		row.add_child(b_add)
		var b_sub := Button.new()
		b_sub.text = "-"
		b_sub.custom_minimum_size = Vector2(36, 28)
		b_sub.pressed.connect(func(id := aid): state.dev_remove_ammo(id, 1))
		row.add_child(b_sub)
	# —— 敌人 ——
	_dev_add_btn(col_enemy["box"], "一键杀敌", func(): state.dev_kill_all_enemies())
	_dev_add_btn(col_enemy["box"], "瞬移邻近", func(): state.dev_teleport_front_enemy(1))
	_dev_add_btn(col_enemy["box"], "瞬移远端", func(): state.dev_teleport_front_enemy(CombatConstants.BOARD_SIZE - 1))
	for item in DataRegistry.all_enemies():
		var eid: int = int(item.get("id", 0))
		var ename: String = str(item.get("name", eid))
		_dev_add_btn(col_enemy["box"], "添加%s" % ename, func(id := eid): state.dev_spawn_enemy(id))


func _dev_make_column(title: String) -> Dictionary:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	root.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(260, 360)
	root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	return {"root": root, "box": box}


func _dev_add_btn(parent: Control, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


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
	turn_label.text = "回合 %d · 第 %d 波 · %s" % [state.turn_index, state.wave_index, ("无限" if state.endless_mode else state.encounter_label())]
	turn_label.add_theme_color_override("font_color", COL_TURN)
	# 动画/射击中才锁按钮；手装会话进行中不锁，以便继续手装或中途开火
	var busy := _busy() or state.is_busy_firing()
	btn_load.disabled = busy or not state.can_load()
	if btn_manual_load != null:
		btn_manual_load.disabled = busy or not state.can_manual_load()
	btn_fire.disabled = busy or not state.can_fire()
	btn_roll.disabled = busy or not state.can_start_roll()
	btn_unload.disabled = busy or not state.can_unload()
	btn_next_wave.disabled = busy or not state.can_start_next_wave()
	_refresh_board()
	if not _wheel_animating:
		_refresh_mag()
	_refresh_bag_list()
	_refresh_muzzle_hud()
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
				elif state.needs_endless_shop():
					result_label.text = "奖励已领取 · 请先逛商店"
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
	# 含 hp<=0 尸体（pace 开火推迟移除），便于致死先飚血再消失
	for e in state.enemies:
		if e == null:
			continue
		by_cell[e.cell] = e
	for i in CombatConstants.BOARD_SIZE:
		var slot: Control = board_row.get_child(i) as Control
		var unit: Panel = slot.get_node_or_null("UnitBody") as Panel
		if unit == null:
			continue
		# 非抖动中：强制贴地（防止旧 offset 抖动把单位留在空中）
		var shaking: bool = false
		if _cell_shake_tweens.has(i):
			var tw_live: Tween = _cell_shake_tweens[i] as Tween
			shaking = tw_live != null and is_instance_valid(tw_live) and tw_live.is_running()
		if not shaking:
			unit.position = _unit_rest_position()
		var info: Label = unit.get_node("VBox/Info")
		var hp_bar: ProgressBar = unit.get_node("VBox/HpBar")
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(8)
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		if i == CombatConstants.PLAYER_CELL:
			unit.visible = true
			style.bg_color = Color(0.2, 0.48, 0.92, 0.98)
			style.border_color = Color(0.65, 0.88, 1.0)
			style.set_border_width_all(3)
			info.text = "玩家\n%d" % state.player_hp
			info.add_theme_color_override("font_color", Color(1, 1, 1))
			info.add_theme_font_size_override("font_size", 15)
			hp_bar.visible = true
			hp_bar.max_value = state.player_max_hp
			hp_bar.value = state.player_hp
			_style_hp_bar(hp_bar, Color(0.35, 0.85, 0.45))
		elif by_cell.has(i):
			var e: EnemyInstance = by_cell[i]
			unit.visible = true
			style.bg_color = Color(0.78, 0.22, 0.24, 0.98)
			if state.can_attack_player(e):
				style.border_color = Color(1.0, 0.88, 0.2)
				style.set_border_width_all(4)
			else:
				style.border_color = Color(0.98, 0.55, 0.5)
				style.set_border_width_all(2)
			var st := e.status_text()
			var tag_s := ",".join(e.tags) if e.tags.size() > 0 else ""
			info.text = "%s\n%d%s%s" % [
				e.name_zh, e.hp,
				("\n" + tag_s) if tag_s != "" else "",
				("\n" + st) if st != "" else ""
			]
			info.add_theme_color_override("font_color", Color(1, 0.95, 0.95))
			info.add_theme_font_size_override("font_size", 13)
			hp_bar.visible = true
			hp_bar.max_value = maxi(e.max_hp, 1)
			hp_bar.value = e.hp
			_style_hp_bar(hp_bar, Color(0.95, 0.35, 0.3))
		else:
			# 空格：不画地块色块，只留线上位
			unit.visible = false
			hp_bar.visible = false
			info.text = ""
		unit.add_theme_stylebox_override("panel", style)


func _style_hp_bar(bar: ProgressBar, fill: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)


func _refresh_hud_only() -> void:
	## 刷新顶栏/棋盘/按钮等，不碰转盘角度（逐步装弹/射击动画用）。
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
	turn_label.text = "回合 %d · 第 %d 波 · %s" % [state.turn_index, state.wave_index, ("无限" if state.endless_mode else state.encounter_label())]
	turn_label.add_theme_color_override("font_color", COL_TURN)
	# 与 _refresh 一致：手装会话本身不锁 手装/开火
	var busy := _busy() or state.is_busy_firing()
	btn_load.disabled = busy or not state.can_load()
	if btn_manual_load != null:
		btn_manual_load.disabled = busy or not state.can_manual_load()
	btn_fire.disabled = busy or not state.can_fire()
	btn_roll.disabled = busy or not state.can_start_roll()
	btn_unload.disabled = busy or not state.can_unload()
	btn_next_wave.disabled = busy or not state.can_start_next_wave()
	_refresh_board()
	_refresh_bag_list()
	_refresh_muzzle_hud()


func _refresh_mag_contents() -> void:
	## 只更新六仓内容与高亮，绝不抢跑旋转角度。
	_paint_mag_chambers()


func _refresh_mag() -> void:
	var start_i: int = state.magazine.start_index
	# 逐步装/射/滚/Tween 期间禁止瞬间对齐，否则会跳过 60° 动画并造成标位错位
	if not _wheel_animating and not _loading and not _firing and not _rolling:
		var want := float(start_i)
		if absf(fposmod(_wheel_visual_steps, float(CombatConstants.MAGAZINE_SIZE)) - want) > 0.01:
			_apply_disk_rotation(want)
	_paint_mag_chambers()


func _paint_mag_chambers() -> void:
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
			info.text = "空"
			info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
			panel.modulate = Color(1, 1, 1, 1)
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
			info.text = short
			info.add_theme_color_override("font_color", colors["fg"])
			# 临时额外罪孽：半透明
			if state.magazine.is_slot_temporary(slot_i):
				panel.modulate = Color(1, 1, 1, 0.48)
			else:
				panel.modulate = Color(1, 1, 1, 1)
		# 高亮跟屏幕固定标走：用盘面视觉步数，避免逻辑 start 已+1 而 Tween 未完成时错位
		var visual_start: int = int(round(fposmod(_wheel_visual_steps, float(CombatConstants.MAGAZINE_SIZE))))
		var at_fire: bool = slot_i == posmod(visual_start + CombatConstants.FIRE_PORT_OFFSET_STEPS, CombatConstants.MAGAZINE_SIZE)
		var at_load: bool = slot_i == posmod(visual_start + CombatConstants.LOAD_PORT_OFFSET_STEPS, CombatConstants.MAGAZINE_SIZE)
		if _loading and at_load:
			style.border_color = Color(0.35, 0.95, 0.7)
			style.set_border_width_all(4)
		elif at_fire:
			style.border_color = Color(1.0, 0.15, 0.12)
			style.set_border_width_all(4)
			if _firing:
				style.bg_color = style.bg_color.lightened(0.25)
		panel.add_theme_stylebox_override("panel", style)
