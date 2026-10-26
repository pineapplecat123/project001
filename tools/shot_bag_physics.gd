extends SceneTree
## xvfb 截弹药物理盒：进战斗 → 多弹种入袋 → 等物理落下 → 截图
func _initialize() -> void:
	var sc: PackedScene = load("res://scenes/combat.tscn")
	var ui = sc.instantiate()
	root.add_child(ui)
	await create_timer(0.6).timeout
	var st = ui.state
	st.dev_add_ammo(4, 3)  # yellow
	st.dev_add_ammo(8, 2)  # gold
	st.dev_add_ammo(14, 2) # water
	st.dev_add_ammo(15, 2) # thunder
	st.dev_add_ammo(13, 2) # fire
	ui._refresh()
	# let physics settle
	await create_timer(1.8).timeout
	var vp := root.get_viewport()
	var img: Image = vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://docs/shots")
	var path := "res://docs/shots/12_bag_physics_box.png"
	img.save_png(path)
	print("saved ", path, " size=", img.get_width(), "x", img.get_height())
	# crop bag region roughly if bag_panel known
	var bag = ui.bag_panel
	if bag != null:
		var r: Rect2 = bag.get_global_rect()
		var x := int(clampf(r.position.x, 0, img.get_width() - 1))
		var y := int(clampf(r.position.y, 0, img.get_height() - 1))
		var w := int(mini(r.size.x, img.get_width() - x))
		var h := int(mini(r.size.y, img.get_height() - y))
		if w > 8 and h > 8:
			var crop := img.get_region(Rect2i(x, y, w, h))
			crop.save_png("res://docs/shots/12_bag_physics_box_crop.png")
			print("saved crop ", w, "x", h)
	print("balls=", ui._bag_physics.ball_count() if ui._bag_physics else -1)
	quit(0)
