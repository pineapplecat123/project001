class_name BagPhysicsBox
extends Control
## 弹药袋物理盒：袋内每发为带重力/碰撞的小球（Control 内自研圆盘物理，等价 RigidBody2D，利于嵌 UI / Web）。

signal ball_hover(ammo_id: int)
signal ball_hover_exit(ammo_id: int)
signal ball_press(ammo_id: int)
signal ball_long_press_tick(ammo_id: int)  ## 按下持续时由外部计时；本控件发 press/release

const GRAVITY := 1400.0
const DEFAULT_RADIUS := 12.0
const MIN_RADIUS := 8.0
const MAX_BALLS_SOFT := 64
const RESTITUTION := 0.28
const WALL_FRICTION := 0.82
const AIR_DRAG := 0.995
const SLEEP_SPEED := 12.0
const WALL_PAD := 5.0
const SPAWN_JITTER := 18.0

var color_lookup: Callable = Callable()  ## (ammo_id) -> {bg, fg}
var name_lookup: Callable = Callable()  ## (ammo_id) -> short glyph

var _balls: Array = []  # each: {id, pos:Vector2, vel:Vector2, r:float, asleep:bool, freeze:int}
var _hover_ammo: int = -1
var _pressed_ammo: int = -1
var _wall_color := Color(0.55, 0.38, 0.18, 1.0)
var _floor_color := Color(0.42, 0.28, 0.12, 1.0)
var _bg_color := Color(0.08, 0.07, 0.06, 0.92)
var _rim_color := Color(0.92, 0.72, 0.35, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(200, 200)


func ball_count() -> int:
	return _balls.size()


func clear_balls() -> void:
	_balls.clear()
	_hover_ammo = -1
	_pressed_ammo = -1
	queue_redraw()


## 与袋内弹药同步。ammo_ids 可含重复；temps 与之等长时标记临时额外罪孽（半透明）。
func sync_ammo_ids(ammo_ids: Array, temps: Array = []) -> void:
	var want: Dictionary = {}  # key "id:t" -> count
	for i in ammo_ids.size():
		var aid: int = int(ammo_ids[i])
		var is_temp: bool = bool(temps[i]) if i < temps.size() else false
		var key: String = "%d:%d" % [aid, 1 if is_temp else 0]
		want[key] = int(want.get(key, 0)) + 1
	var have: Dictionary = {}
	for b in _balls:
		var key2: String = "%d:%d" % [int(b["id"]), 1 if bool(b.get("temp", false)) else 0]
		have[key2] = int(have.get(key2, 0)) + 1
	for key3 in have.keys():
		var extra: int = int(have[key3]) - int(want.get(key3, 0))
		while extra > 0:
			var parts: PackedStringArray = str(key3).split(":")
			_remove_one_ball(int(parts[0]), parts.size() > 1 and parts[1] == "1")
			extra -= 1
	for key4 in want.keys():
		var miss: int = int(want[key4]) - int(have.get(key4, 0))
		var parts2: PackedStringArray = str(key4).split(":")
		var aid4: int = int(parts2[0])
		var t4: bool = parts2.size() > 1 and parts2[1] == "1"
		for _i in miss:
			_spawn_ball(aid4, t4)
	_update_radii_for_count()
	queue_redraw()


func _update_radii_for_count() -> void:
	var n: int = _balls.size()
	var r: float = DEFAULT_RADIUS
	if n > MAX_BALLS_SOFT:
		r = maxf(MIN_RADIUS, DEFAULT_RADIUS * float(MAX_BALLS_SOFT) / float(n))
	for b in _balls:
		b["r"] = r


func _spawn_ball(ammo_id: int, temporary: bool = false) -> void:
	var sz := size
	if sz.x < 8.0 or sz.y < 8.0:
		sz = custom_minimum_size
	var r: float = DEFAULT_RADIUS
	var x: float = sz.x * 0.5 + randf_range(-SPAWN_JITTER, SPAWN_JITTER)
	x = clampf(x, WALL_PAD + r, maxf(WALL_PAD + r, sz.x - WALL_PAD - r))
	var y: float = WALL_PAD + r + randf_range(0.0, 10.0)
	_balls.append({
		"id": ammo_id,
		"temp": temporary,
		"pos": Vector2(x, y),
		"vel": Vector2(randf_range(-40.0, 40.0), randf_range(0.0, 30.0)),
		"r": r,
		"asleep": false,
		"freeze": 0,
	})


func _remove_one_ball(ammo_id: int, temporary: bool = false) -> void:
	# 优先移除靠上的同 id+temp 球，看起来像被「抓走」
	var best_i := -1
	var best_top := INF
	for i in _balls.size():
		var b: Dictionary = _balls[i]
		if int(b["id"]) != ammo_id:
			continue
		if bool(b.get("temp", false)) != temporary:
			continue
		if float(b["pos"].y) < best_top:
			best_top = float(b["pos"].y)
			best_i = i
	if best_i >= 0:
		_balls.remove_at(best_i)


func _physics_process(delta: float) -> void:
	if not visible or _balls.is_empty():
		return
	var sz := size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	var left := WALL_PAD
	var right := sz.x - WALL_PAD
	var top := WALL_PAD
	var bottom := sz.y - WALL_PAD
	# integrate
	for b in _balls:
		if bool(b["asleep"]):
			continue
		var vel: Vector2 = b["vel"]
		vel.y += GRAVITY * delta
		vel *= AIR_DRAG
		var pos: Vector2 = b["pos"]
		pos += vel * delta
		var r: float = float(b["r"])
		# walls
		if pos.x - r < left:
			pos.x = left + r
			vel.x = -vel.x * RESTITUTION
			vel.y *= WALL_FRICTION
		elif pos.x + r > right:
			pos.x = right - r
			vel.x = -vel.x * RESTITUTION
			vel.y *= WALL_FRICTION
		if pos.y - r < top:
			pos.y = top + r
			vel.y = absf(vel.y) * RESTITUTION
		elif pos.y + r > bottom:
			pos.y = bottom - r
			vel.y = -vel.y * RESTITUTION
			vel.x *= WALL_FRICTION
			if absf(vel.y) < SLEEP_SPEED and absf(vel.x) < SLEEP_SPEED:
				b["freeze"] = int(b["freeze"]) + 1
				if int(b["freeze"]) > 8:
					vel = Vector2.ZERO
					b["asleep"] = true
			else:
				b["freeze"] = 0
		else:
			b["freeze"] = 0
		b["pos"] = pos
		b["vel"] = vel
	# ball-ball (simple positional correction + bounce)
	var n: int = _balls.size()
	for i in n:
		var a: Dictionary = _balls[i]
		for j in range(i + 1, n):
			var c: Dictionary = _balls[j]
			var pa: Vector2 = a["pos"]
			var pc: Vector2 = c["pos"]
			var delta_p: Vector2 = pc - pa
			var dist_sq: float = delta_p.length_squared()
			var ra: float = float(a["r"])
			var rc: float = float(c["r"])
			var min_d: float = ra + rc
			if dist_sq <= 0.0001 or dist_sq >= min_d * min_d:
				continue
			var dist: float = sqrt(dist_sq)
			var nrm: Vector2 = delta_p / dist
			var overlap: float = min_d - dist
			var push: Vector2 = nrm * (overlap * 0.5)
			a["pos"] = pa - push
			c["pos"] = pc + push
			var va: Vector2 = a["vel"]
			var vc: Vector2 = c["vel"]
			var rel: float = (vc - va).dot(nrm)
			if rel < 0.0:
				var impulse: float = -(1.0 + RESTITUTION) * rel * 0.5
				a["vel"] = va - nrm * impulse
				c["vel"] = vc + nrm * impulse
			a["asleep"] = false
			c["asleep"] = false
			a["freeze"] = 0
			c["freeze"] = 0
	queue_redraw()


func _draw() -> void:
	var sz := size
	# box interior
	draw_rect(Rect2(Vector2.ZERO, sz), _bg_color, true)
	# wooden rim
	var t := WALL_PAD
	draw_rect(Rect2(0, sz.y - t, sz.x, t), _floor_color, true)
	draw_rect(Rect2(0, 0, t, sz.y), _wall_color, true)
	draw_rect(Rect2(sz.x - t, 0, t, sz.y), _wall_color, true)
	draw_rect(Rect2(0, 0, sz.x, t * 0.6), _wall_color, true)
	draw_rect(Rect2(Vector2.ZERO, sz), _rim_color, false, 2.0)
	# balls
	for b in _balls:
		var aid: int = int(b["id"])
		var pos: Vector2 = b["pos"]
		var r: float = float(b["r"])
		var colors: Dictionary = {"bg": Color(0.85, 0.85, 0.88), "fg": Color(0.1, 0.1, 0.1)}
		if color_lookup.is_valid():
			var looked = color_lookup.call(aid)
			if typeof(looked) == TYPE_DICTIONARY:
				colors = looked
		var bg: Color = colors.get("bg", Color(0.85, 0.85, 0.88))
		var fg: Color = colors.get("fg", Color(0.1, 0.1, 0.1))
		if bool(b.get("temp", false)):
			bg.a *= 0.45
			fg.a *= 0.55
		draw_circle(pos, r, bg)
		draw_arc(pos, r, 0.0, TAU, 24, Color(0.1, 0.1, 0.12, 0.75), 1.5, true)
		var glyph := "?"
		if name_lookup.is_valid():
			glyph = str(name_lookup.call(aid))
		var font := get_theme_default_font()
		var fsize := int(maxi(9, int(r * 0.95)))
		if font != null:
			# draw_string 的 y 是基线：用 ascent 把单字框中心对齐球心
			var ts := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
			var ascent := font.get_ascent(fsize)
			var text_pos := Vector2(pos.x - ts.x * 0.5, pos.y - ts.y * 0.5 + ascent)
			draw_string(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, fg)
	# empty hint
	if _balls.is_empty():
		var font2 := get_theme_default_font()
		if font2 != null:
			var empty := "（空盒）"
			var es := font2.get_string_size(empty, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			var ea := font2.get_ascent(14)
			draw_string(
				font2,
				Vector2(sz.x * 0.5 - es.x * 0.5, sz.y * 0.5 - es.y * 0.5 + ea),
				empty, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.6, 0.5)
			)


func _ball_at_pointer(local_pos: Vector2 = Vector2.INF) -> Variant:
	var p := local_pos
	if p.x == INF:
		p = get_local_mouse_position()
	# 从上往下优先（后画的在上层，近似取最近）
	var best = null
	var best_d := INF
	for b in _balls:
		var d: float = p.distance_to(b["pos"])
		if d <= float(b["r"]) + 1.0 and d < best_d:
			best_d = d
			best = b
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var b = _ball_at_pointer()
		var aid := int(b["id"]) if b != null else -1
		if aid != _hover_ammo:
			if _hover_ammo >= 0:
				ball_hover_exit.emit(_hover_ammo)
			_hover_ammo = aid
			if aid >= 0:
				ball_hover.emit(aid)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var b2 = _ball_at_pointer(mb.position)
			if mb.pressed:
				if b2 != null:
					_pressed_ammo = int(b2["id"])
					ball_press.emit(_pressed_ammo)
					# wake ball a bit
					b2["asleep"] = false
					b2["vel"] = Vector2(b2["vel"]) + Vector2(randf_range(-30, 30), -40)
			else:
				if _pressed_ammo >= 0:
					_pressed_ammo = -1
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var b3 = _ball_at_pointer(st.position)
		if st.pressed and b3 != null:
			_pressed_ammo = int(b3["id"])
			ball_press.emit(_pressed_ammo)
		elif not st.pressed:
			_pressed_ammo = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hover_ammo >= 0:
			ball_hover_exit.emit(_hover_ammo)
			_hover_ammo = -1
