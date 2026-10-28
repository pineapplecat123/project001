extends GutTest
## 弹药盒物理球：与袋 id 列表增量同步。


func test_sync_ammo_ids_adds_and_removes() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.custom_minimum_size = Vector2(200, 200)
	box.size = Vector2(200, 200)
	add_child_autoqfree(box)
	box.sync_ammo_ids([1, 1, 8])
	assert_eq(box.ball_count(), 3)
	box.sync_ammo_ids([1, 8])
	assert_eq(box.ball_count(), 2)
	box.sync_ammo_ids([])
	assert_eq(box.ball_count(), 0)
	box.sync_ammo_ids([14, 15, 15, 15])
	assert_eq(box.ball_count(), 4)


func test_physics_step_moves_balls_down() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.custom_minimum_size = Vector2(220, 240)
	box.size = Vector2(220, 240)
	add_child_autoqfree(box)
	box.sync_ammo_ids([1])
	assert_eq(box.ball_count(), 1)
	var y0: float = float(box._balls[0]["pos"].y)
	for _i in 30:
		box._physics_process(1.0 / 60.0)
	var y1: float = float(box._balls[0]["pos"].y)
	assert_gt(y1, y0, "gravity should pull ball downward")


func test_super_round_glow_draw_smoke() -> void:
	## 超级回合在袋内应可绘制金色辉光路径（不报错、球仍在）。
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.custom_minimum_size = Vector2(200, 200)
	box.size = Vector2(200, 200)
	box.color_lookup = func(aid: int) -> Dictionary:
		return {"bg": Color(1.0, 0.86, 0.22), "fg": Color(0.18, 0.1, 0.02)}
	box.name_lookup = func(_aid: int) -> String:
		return "超"
	add_child_autoqfree(box)
	box.sync_ammo_ids([FireResolver.ID_SUPER_ROUND])
	assert_eq(box.ball_count(), 1)
	box.queue_redraw()
	await get_tree().process_frame
	assert_eq(box.ball_count(), 1)


func test_armor_pierce_glow_draw_smoke() -> void:
	## 穿甲在袋内应可绘制钢青辉光路径（不报错、球仍在）。
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.custom_minimum_size = Vector2(200, 200)
	box.size = Vector2(200, 200)
	box.color_lookup = func(aid: int) -> Dictionary:
		return {"bg": Color(0.55, 0.78, 0.92), "fg": Color(0.04, 0.12, 0.2)}
	box.name_lookup = func(_aid: int) -> String:
		return "甲"
	add_child_autoqfree(box)
	box.sync_ammo_ids([FireResolver.ID_ARMOR_PIERCE])
	assert_eq(box.ball_count(), 1)
	box.queue_redraw()
	await get_tree().process_frame
	assert_eq(box.ball_count(), 1)
