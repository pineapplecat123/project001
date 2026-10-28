extends SceneTree
## Headless probe: death plasma ColorRect / usec / pool pressure.
## Usage: godot --headless -s tools/blood_death_perf_probe.gd

func _initialize() -> void:
	var ui := Control.new()
	ui.set_script(load("res://scripts/combat/combat_ui.gd"))
	# Minimal layout so drops do not instantly land
	ui.size = Vector2(1280, 720)
	ui.position = Vector2.ZERO
	root.add_child(ui)
	# Fake board with GroundSeg near bottom
	var board := HBoxContainer.new()
	board.name = "BoardRow"
	ui.add_child(board)
	ui.set("board_row", board)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(80, 200)
	board.add_child(slot)
	var gseg := ColorRect.new()
	gseg.name = "GroundSeg"
	gseg.size = Vector2(80, 8)
	gseg.position = Vector2(0, 500)
	slot.add_child(gseg)
	await process_frame
	await process_frame

	var death_min: int = ui.BLOOD_DEATH_BURST_MIN
	var death_max: int = ui.BLOOD_DEATH_BURST_MAX
	var active_max: int = ui.BLOOD_ACTIVE_MAX
	var pool_max: int = ui.BLOOD_POOL_MAX
	var trail: int = ui.BLOOD_TRAIL_HISTORY
	print("PERF_BLOOD_DEATH caps death=%d-%d active_max=%d pool_max=%d trail=%d" % [
		death_min, death_max, active_max, pool_max, trail
	])
	print("PERF_BLOOD_DEATH estimated_peak_flight_rects=%d" % [active_max * (1 + trail)])

	var center := Vector2(640, 280)
	var before: int = _count_visible_color_rects(ui)
	var t0: int = Time.get_ticks_usec()
	ui._spawn_blood_burst(center, 24, Vector2.ZERO, true)
	var t1: int = Time.get_ticks_usec()
	var active1: int = ui._blood_active_drops
	var pool1: int = ui._blood_pool.size()
	var vis1: int = _count_visible_color_rects(ui)
	var all1: int = _count_color_rects(ui)
	print("PERF_BLOOD_DEATH cold_spawn_usec=%d active_drops=%d visible_rects=%d(+%d) total_rects=%d pool=%d" % [
		t1 - t0, active1, vis1, vis1 - before, all1, pool1
	])

	# Warm second death while first still flying
	var t2: int = Time.get_ticks_usec()
	ui._spawn_blood_burst(center + Vector2(100, 0), 24, Vector2.ZERO, true)
	var t3: int = Time.get_ticks_usec()
	var active2: int = ui._blood_active_drops
	var vis2: int = _count_visible_color_rects(ui)
	print("PERF_BLOOD_DEATH second_spawn_usec=%d active_drops=%d visible_rects=%d (cap_room=%d)" % [
		t3 - t2, active2, vis2, active_max - active2
	])

	# Hit burst comparison
	var t4: int = Time.get_ticks_usec()
	ui._spawn_blood_burst(center + Vector2(-100, 0), 12, Vector2.LEFT, false)
	var t5: int = Time.get_ticks_usec()
	print("PERF_BLOOD_HIT spawn_usec=%d active_drops=%d visible_rects=%d" % [
		t5 - t4, ui._blood_active_drops, _count_visible_color_rects(ui)
	])

	# Theoretical old vs new
	print("PERF_BLOOD_DEATH compare old_death_max_rects=%d new_death_max_rects=%d (+%d%%)" % [
		40 * (1 + trail), death_max * (1 + trail),
		int(round(100.0 * float(death_max - 40) / 40.0))
	])
	print("OK blood death perf probe")
	quit(0)


func _count_color_rects(n: Node) -> int:
	var c := 0
	if n is ColorRect:
		c = 1
	for ch in n.get_children():
		c += _count_color_rects(ch)
	return c


func _count_visible_color_rects(n: Node) -> int:
	var c := 0
	if n is ColorRect and (n as CanvasItem).visible:
		c = 1
	for ch in n.get_children():
		c += _count_visible_color_rects(ch)
	return c
