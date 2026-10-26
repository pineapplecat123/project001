extends SceneTree
func _initialize() -> void:
	call_deferred("_go")
func _go() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/shots")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("main fail %s" % err); quit(1); return
	await process_frame
	await process_frame
	await create_timer(0.6).timeout
	_save("10_font_main")
	# Print theme font info
	var sc = current_scene
	if sc:
		var theme = sc.theme
		print("MAIN theme=", theme)
		if theme:
			var f = theme.default_font
			print("MAIN default_font=", f, " path=", f.resource_path if f else null)
		var title = sc.get_node_or_null("%TitleLabel")
		if title == null:
			title = sc.find_child("TitleLabel", true, false)
		if title:
			print("TITLE text=", JSON.stringify(title.text), " font=", title.get_theme_font("font"))
	err = change_scene_to_file("res://scenes/combat.tscn")
	if err != OK:
		push_error("combat fail"); quit(1); return
	await process_frame
	await process_frame
	await create_timer(0.7).timeout
	_save("11_font_combat")
	var c = current_scene
	if c and c.has_method("get"):
		pass
	var phase = c.get_node_or_null("%PhaseLabel") if c else null
	if phase:
		print("PHASE text=", JSON.stringify(phase.text), " font=", phase.get_theme_font("font"))
	print("SHOTS_DONE")
	quit(0)
func _save(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://docs/shots/%s.png" % name)
	var e := img.save_png(path)
	print("SHOT %s err=%s %sx%s" % [name, e, img.get_width(), img.get_height()])
