extends SceneTree
## Review shots: HUD, ammo detail (no dimmer), damage float, endless shop.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/shots")
	var err := change_scene_to_file("res://scenes/combat.tscn")
	if err != OK:
		push_error("change_scene failed %s" % err)
		quit(1)
		return
	await process_frame
	await process_frame
	await create_timer(0.7).timeout
	var scene = current_scene
	if scene == null:
		push_error("no scene")
		quit(1)
		return
	# Force endless for shop shot later
	if scene.state != null:
		scene.state.start_graybox(4242, true)
		await process_frame
		await process_frame
	var bag: Control = scene.get_node("%BagPanel") as Control
	var action: Control = scene.get_node_or_null("Margin/RootVBox/BottomSection/CombatBlock/ActionCol") as Control
	var combat_block: Control = scene.get_node_or_null("Margin/RootVBox/BottomSection/CombatBlock") as Control
	var left_pad: Control = scene.get_node_or_null("Margin/RootVBox/BottomSection/BottomLeftPad") as Control
	var pad: Control = scene.get_node_or_null("Margin/RootVBox/BottomSection/BagRightPad") as Control
	var board: Control = scene.get_node("%BoardRow") as Control
	var top_sec: Control = scene.get_node_or_null("Margin/RootVBox/TopSection") as Control
	var vp_w := float(root.get_viewport().get_visible_rect().size.x)
	if board != null and top_sec != null:
		var board_mid := board.global_position.x + board.size.x * 0.5
		var top_mid := top_sec.global_position.x + top_sec.size.x * 0.5
		print("BOARD_LAYOUT x=%.1f w=%.1f mid=%.1f top_mid=%.1f delta=%.1f" % [
			board.global_position.x, board.size.x, board_mid, top_mid, board_mid - top_mid
		])
	if bag != null:
		var gap_left := bag.global_position.x - (action.global_position.x + action.size.x) if action != null else -1.0
		var pad_right := vp_w - (bag.global_position.x + bag.size.x)
		var cluster_left := combat_block.global_position.x if combat_block != null else -1.0
		var cluster_right := bag.global_position.x + bag.size.x
		var cluster_mid := (cluster_left + cluster_right) * 0.5 if combat_block != null else -1.0
		print("BAG_LAYOUT x=%.1f w=%.1f gap_vs_action=%.1f pad_right=%.1f vp_w=%.1f left_pad_w=%.1f right_pad_w=%.1f cluster_mid=%.1f vp_mid=%.1f" % [
			bag.global_position.x, bag.size.x, gap_left, pad_right, vp_w,
			left_pad.size.x if left_pad != null else -1.0,
			pad.size.x if pad != null else -1.0,
			cluster_mid, vp_w * 0.5
		])
	var log_panel: Control = scene.get_node_or_null("Margin/RootVBox/BottomSection/LogPanel") as Control
	if log_panel != null:
		print("LOG_LAYOUT x=%.1f w=%.1f right_edge=%.1f vp_w=%.1f" % [
			log_panel.global_position.x, log_panel.size.x,
			log_panel.global_position.x + log_panel.size.x, vp_w
		])
	if action != null:
		print("ACTION_LAYOUT x=%.1f w=%.1f h=%.1f" % [action.global_position.x, action.size.x, action.size.y])
	if combat_block != null and bag != null and log_panel != null:
		var gap1 := bag.global_position.x - (combat_block.global_position.x + combat_block.size.x)
		var gap2 := log_panel.global_position.x - (bag.global_position.x + bag.size.x)
		var cluster_l := combat_block.global_position.x
		var cluster_r := log_panel.global_position.x + log_panel.size.x
		var cluster_mid := (cluster_l + cluster_r) * 0.5
		print("CLUSTER combat_x=%.1f combat_w=%.1f bag_x=%.1f bag_w=%.1f log_x=%.1f log_w=%.1f gap_cb=%.1f gap_bl=%.1f mid=%.1f vp_mid=%.1f left_pad=%.1f right_pad=%.1f" % [
			combat_block.global_position.x, combat_block.size.x,
			bag.global_position.x, bag.size.x,
			log_panel.global_position.x, log_panel.size.x,
			gap1, gap2, cluster_mid, vp_w * 0.5,
			left_pad.size.x if left_pad != null else -1.0,
			pad.size.x if pad != null else -1.0
		])
	_save("01_combat_hud")
	# Ammo detail long-press style without dimmer
	var bag_list: VBoxContainer = scene.get_node("%BagList")
	var cell: Control = null
	for c in bag_list.get_children():
		if c is GridContainer and c.get_child_count() > 0:
			cell = c.get_child(0)
			break
	if cell != null:
		scene._show_ammo_detail(1, cell, true, false)
		await process_frame
		await process_frame
		await create_timer(0.2).timeout
		# Ensure dimmer off for detail
		if scene.dimmer != null:
			scene.dimmer.visible = false
		_save("02_ammo_detail_no_dimmer")
		scene._hide_ammo_detail()
	# Damage floats: stagger so -5 / -3 stay readable mid-arc
	if scene.state != null:
		for e in scene.state.alive_enemies():
			scene._spawn_damage_float(e.cell, 5)
		await process_frame
		await create_timer(0.12).timeout
		for e in scene.state.alive_enemies():
			scene._spawn_damage_float(e.cell, 3)
		await process_frame
		await create_timer(0.28).timeout
		_save("03_damage_float_mid")
	# Endless shop after fake wave-5 win
	if scene.state != null:
		var cs = scene.state
		cs.phase = cs.Phase.AWAIT_LOAD
		cs._clear_reward_state()
		cs.endless_mode = true
		cs.endless_shop_done = true
		cs.wave_index = 5
		cs.gold = 40
		cs.enemies.clear()
		cs.dev_spawn_enemy(1, 8)
		cs.dev_kill_all_enemies()
		cs.skip_reward_for_gold()
		await process_frame
		scene._open_endless_shop()
		await process_frame
		await process_frame
		await create_timer(0.25).timeout
		_save("04_endless_shop")
	print("SHOTS_DONE")
	quit(0)


func _save(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no image for " + name)
		return
	var abs_path := ProjectSettings.globalize_path("res://docs/shots/%s.png" % name)
	var serr := img.save_png(abs_path)
	print("SHOT %s -> %s err=%s %sx%s" % [name, abs_path, serr, img.get_width(), img.get_height()])
