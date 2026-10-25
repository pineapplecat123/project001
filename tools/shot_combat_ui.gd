extends SceneTree
## One-shot: open combat, wait a beat, save screenshot, quit.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var err := change_scene_to_file("res://scenes/combat.tscn")
	if err != OK:
		push_error("change_scene failed %s" % err)
		quit(1)
		return
	await process_frame
	await process_frame
	await create_timer(0.8).timeout
	var win := root
	var img: Image = win.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no image")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://tools/out")
	var abs_path := ProjectSettings.globalize_path("res://tools/out/combat_hud_uncrop.png")
	var serr := img.save_png(abs_path)
	print("SHOT_RESULT=%s path=%s size=%sx%s" % [serr, abs_path, img.get_width(), img.get_height()])
	quit(0 if serr == OK else 1)
