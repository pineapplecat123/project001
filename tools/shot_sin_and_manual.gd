extends SceneTree
## 实机：选罪孽 → 袋 10+5 → 手装 → 愤怒/傲慢/贪婪效果；截图。不直接引用 CombatState/FireResolver（-s 下 autoload 未就绪会编译失败）。
const ID_WRATH := 16
const ID_PRIDE := 17
const ID_GREED := 18
const ID_WHITE := 1
const ID_ZOMBIE := 6
const ID_SUPER := 7

func _ints(vals: Array) -> Array:
	var out: Array[int] = []
	for v in vals:
		out.append(int(v))
	return out

func _initialize() -> void:
	var sc: PackedScene = load("res://scenes/combat.tscn")
	var ui = sc.instantiate()
	root.add_child(ui)
	await create_timer(0.55).timeout
	print("sin_open=", ui._sin_pick_open, " bag_before=", ui.state.bag.size())
	DirAccess.make_dir_recursive_absolute("res://docs/shots")
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("res://docs/shots/13_sin_pick.png")
	print("saved 13_sin_pick size=", img.get_width(), "x", img.get_height())

	# pick wrath via UI
	ui._on_sin_picked(ID_WRATH)
	await create_timer(0.45).timeout
	var st = ui.state
	var white := 0
	var sin_n := 0
	for id in st.bag:
		if int(id) == ID_WHITE:
			white += 1
		elif int(id) == ID_WRATH:
			sin_n += 1
	print("bag_total=", st.bag.size(), " white=", white, " wrath=", sin_n, " muzzle=", st.muzzle_status_text())
	assert(white == 10 and sin_n == 5 and st.bag.size() == 15)
	img = root.get_viewport().get_texture().get_image()
	img.save_png("res://docs/shots/14_sin_bag_physics.png")
	if ui.bag_panel:
		var r: Rect2 = ui.bag_panel.get_global_rect()
		var x := int(clampf(r.position.x, 0, img.get_width() - 1))
		var y := int(clampf(r.position.y, 0, img.get_height() - 1))
		var w := int(mini(r.size.x, img.get_width() - x))
		var h := int(mini(r.size.y, img.get_height() - y))
		if w > 8 and h > 8:
			var crop := img.get_region(Rect2i(x, y, w, h))
			crop.save_png("res://docs/shots/14_sin_bag_physics_crop.png")
			print("saved crop ", w, "x", h)
	print("balls=", ui._bag_physics.ball_count() if ui._bag_physics else -1)
	assert(ui.btn_manual_load != null)
	assert(ui.btn_manual_load.get_parent() != null)
	print("manual_btn_text=", ui.btn_manual_load.text, " visible=", ui.btn_manual_load.visible, " disabled=", ui.btn_manual_load.disabled)
	assert(ui.btn_manual_load.text == "手装")

	# manual load one round
	assert(st.can_manual_load())
	ui._on_manual_load()
	await create_timer(0.7).timeout
	print("after_hand_load mag=", st.magazine.loaded_count(), " session=", st.is_busy_loading())
	assert(st.magazine.loaded_count() == 1)

	# --- effect checks on a fresh state via preload (autoloads ready now) ---
	var CombatStateScr: GDScript = load("res://scripts/combat/combat_state.gd") as GDScript

	# wrath pack-of-3 self damage
	var cs2 = CombatStateScr.new(77)
	cs2.start_graybox(77, false, ID_WRATH)
	cs2.enemies[0].hp = 999
	cs2.bag.clear()
	for id in [ID_WRATH, ID_WRATH, ID_WRATH, ID_WHITE, ID_WHITE, ID_WHITE]:
		cs2.bag.append(id)
	var hp0: int = cs2.player_hp
	cs2.do_load()
	print("wrath3 self dmg: hp ", hp0, "->", cs2.player_hp, " ok=", cs2.player_hp == hp0 - 6)
	assert(cs2.player_hp == hp0 - 6)

	# wrath muzzle +1 stack, dmg *2 on base 3 white? wrath ammo base — check dealt
	cs2 = CombatStateScr.new(78)
	cs2.start_graybox(78, false, ID_WRATH)
	cs2.enemies.clear()
	cs2.dev_spawn_enemy(1, 4)
	cs2.enemies[0].hp = 200
	cs2.enemies[0].max_hp = 200
	cs2.dev_force_load(_ints([ID_WRATH, ID_WHITE, ID_WHITE, ID_WHITE, ID_WHITE, ID_WHITE]))
	cs2.magazine.set_start(0)
	cs2.begin_fire()
	var h0: int = cs2.enemies[0].hp
	cs2.fire_next_shot()
	var dealt: int = h0 - cs2.enemies[0].hp
	print("wrath muzzle dmg=", dealt, " stacks=", cs2._muzzle_wrath, " text=", cs2.muzzle_status_text())
	assert(dealt == 6)
	assert(cs2._muzzle_wrath == 1)

	# pride pull to front
	cs2 = CombatStateScr.new(79)
	cs2.start_graybox(79, false, ID_PRIDE)
	cs2.enemies.clear()
	cs2.dev_spawn_enemy(1, 8)
	cs2.dev_spawn_enemy(1, 9)
	cs2.bag.clear()
	for id in [ID_PRIDE, ID_PRIDE, ID_PRIDE, ID_WHITE, ID_WHITE, ID_WHITE]:
		cs2.bag.append(id)
	cs2.do_load()
	var sorted = cs2.enemies_sorted_by_cell()
	print("pride cells=", sorted[0].cell, sorted[1].cell)
	assert(sorted[0].cell == 1)

	# greed gold (3 greed → -6? design was gold -= 2 per greed pack? assert matches test)
	cs2 = CombatStateScr.new(80)
	cs2.start_graybox(80, false, ID_GREED)
	cs2.gold = 1
	cs2.bag.clear()
	for id in [ID_GREED, ID_GREED, ID_GREED, ID_WHITE, ID_WHITE, ID_WHITE]:
		cs2.bag.append(id)
	cs2.do_load()
	print("greed gold=", cs2.gold)
	assert(cs2.gold == -5)

	# zombie 50hp + super front summon
	cs2 = CombatStateScr.new(81)
	cs2.start_graybox(81, true, ID_WRATH)
	cs2.enemies.clear()
	cs2.dev_spawn_enemy(ID_ZOMBIE, 8)
	assert(cs2.enemies[0].max_hp == 50)
	print("zombie_hp=", cs2.enemies[0].max_hp)
	cs2.enemies.clear()
	cs2.dev_spawn_enemy(ID_SUPER, 5)
	cs2.bag.clear()
	for _i in 6:
		cs2.bag.append(ID_WHITE)
	cs2.do_load()
	cs2.do_unload()
	var boss_cell := -1
	var z_cell := -1
	for e in cs2.enemies:
		if e.def_id == ID_SUPER:
			boss_cell = e.cell
		if e.def_id == ID_ZOMBIE:
			z_cell = e.cell
	print("super summon front: boss=", boss_cell, " z=", z_cell)
	assert(z_cell == boss_cell - 1)

	# muzzle HUD shot
	st.dev_force_load(_ints([ID_WRATH, ID_WRATH, ID_WHITE, ID_WHITE, ID_WHITE, ID_WHITE]))
	if st.enemies.size() > 0:
		st.enemies[0].hp = 999
	st.begin_fire()
	st.fire_next_shot()
	ui._refresh()
	await create_timer(0.35).timeout
	img = root.get_viewport().get_texture().get_image()
	img.save_png("res://docs/shots/15_sin_muzzle.png")
	print("muzzle_ui=", st.muzzle_status_text())
	print("ALL_LIVE_CHECKS_OK")
	quit(0)
