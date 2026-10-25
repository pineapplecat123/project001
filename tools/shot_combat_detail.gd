extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	change_scene_to_file("res://scenes/combat.tscn")
	await process_frame
	await process_frame
	await create_timer(0.6).timeout
	var scene = current_scene
	# find first bag cell panel
	var bag_list: VBoxContainer = scene.get_node("%BagList")
	var cell: Control = null
	for c in bag_list.get_children():
		if c is GridContainer:
			if c.get_child_count() > 0:
				cell = c.get_child(0)
				break
	scene._show_ammo_detail(1, cell, true, false)
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path("res://tools/out/combat_hud_detail_v024.png")
	img.save_png(abs_path)
	print("SHOT_DETAIL=", abs_path)
	quit(0)
