extends SceneTree
## xvfb：不进罪孽选择；放大愤怒钝圆弹头 + 慢飞枪线特写。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/shots")
	DirAccess.make_dir_recursive_absolute("res://tools/out")
	var err := change_scene_to_file("res://scenes/combat.tscn")
	if err != OK:
		push_error("change_scene failed %s" % err)
		quit(1)
		return
	await process_frame
	await process_frame
	await create_timer(0.4).timeout
	var scene = current_scene
	if scene == null:
		push_error("no scene")
		quit(1)
		return
	# 不 start_graybox，避免罪孽弹窗；直接画放大弹头
	var core := Color(0.75, 0.12, 0.12, 1.0)
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.z_index = 90
	scene.add_child(host)
	host.global_position = Vector2(560, 300)
	var glow = scene._make_shot_bullet_tip(110.0, 90.0, 30.0, scene._shot_head_display_color(core, 0.42, 0.45))
	var body = scene._make_shot_bullet_tip(88.0, 72.0, 24.0, scene._shot_head_display_color(core, 0.38, 1.0))
	var hot = scene._make_shot_bullet_tip(48.0, 32.0, 14.0, scene._shot_head_display_color(core, 0.55, 0.72))
	host.add_child(glow)
	host.add_child(body)
	host.add_child(hot)
	var trail: Line2D = scene._make_shot_trail_line(24.0, core, 1.0, 0.28, 0.95, 0.12)
	host.add_child(trail)
	trail.visible = true
	trail.points = PackedVector2Array([Vector2.ZERO, Vector2(-260.0, 0.0)])
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no image")
		quit(1)
		return
	var full_path := ProjectSettings.globalize_path("res://docs/shots/16_bullet_tip_round.png")
	img.save_png(full_path)
	print("SHOT_FULL=%s %sx%s" % [full_path, img.get_width(), img.get_height()])
	var crop := img.get_region(Rect2i(300, 180, 480, 260))
	var crop_path := ProjectSettings.globalize_path("res://docs/shots/16_bullet_tip_round_crop.png")
	crop.save_png(crop_path)
	print("SHOT_CROP=%s" % crop_path)
	img.save_png(ProjectSettings.globalize_path("res://tools/out/bullet_tip_round_v0275.png"))
	crop.save_png(ProjectSettings.globalize_path("res://tools/out/bullet_tip_round_v0275_crop.png"))
	# 真实飞行
	var outlines: Array[Color] = []
	var waypoints: Array = []
	scene._animate_shot_projectile(Vector2(140, 480), Vector2(1000, 480), core, outlines, waypoints, 1.4)
	await create_timer(0.5).timeout
	var img2: Image = root.get_viewport().get_texture().get_image()
	var fly := ProjectSettings.globalize_path("res://docs/shots/16_bullet_tip_round_fly.png")
	img2.save_png(fly)
	var t := 0.5 / 1.4
	var hx := int(lerpf(140.0, 1000.0, t))
	var hy := 480
	var half := 120
	var fx0 := clampi(hx - half, 0, img2.get_width() - 1)
	var fy0 := clampi(hy - half, 0, img2.get_height() - 1)
	var fcrop := img2.get_region(Rect2i(fx0, fy0, mini(half * 2, img2.get_width() - fx0), mini(half * 2, img2.get_height() - fy0)))
	var fcrop_path := ProjectSettings.globalize_path("res://docs/shots/16_bullet_tip_round_fly_crop.png")
	fcrop.save_png(fcrop_path)
	print("SHOT_FLY=%s" % fly)
	print("SHOT_FLY_CROP=%s at=%s,%s" % [fcrop_path, hx, hy])
	print("SHOT_BULLET_TIP_DONE")
	quit(0)
