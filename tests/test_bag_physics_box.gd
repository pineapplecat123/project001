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
