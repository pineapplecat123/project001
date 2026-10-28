extends GutTest
## 击发黄闪：无白蒙版；转盘前必须 clear；不整段 _firing lightened。


func test_fire_flash_yellow_only_cleared_before_rotate() -> void:
	var f := FileAccess.open("res://scripts/combat/combat_ui.gd", FileAccess.READ)
	assert_not_null(f)
	var text := f.get_as_text()
	assert_true(text.contains("var _fire_flash_slot"), "must track flash slot locally")
	assert_true(text.contains("func _clear_fire_flash"), "must have clear helper")
	assert_true(text.contains("func _begin_fire_flash"), "must have begin helper")
	assert_false(text.contains("lightened(0.25)"), "must not paint white fire mask")
	assert_false(text.contains("_fire_overlay_slot"), "overlay slot renamed away")
	var anim_i := text.find("func _animate_fire_shots")
	assert_gt(anim_i, 0)
	var anim := text.substr(anim_i, text.find("\nfunc ", anim_i + 10) - anim_i)
	var hold_i := anim.find("FIRE_FLASH_HOLD")
	assert_gt(hold_i, 0, "fire loop must await FIRE_FLASH_HOLD")
	var after_hold := anim.substr(hold_i, 280)
	assert_true(after_hold.contains("_clear_fire_flash()"), "clear flash right after flash hold")
	var clear_i := anim.find("_clear_fire_flash()", hold_i)
	var rotate_i := anim.find("_animate_disk_to", clear_i)
	assert_gt(rotate_i, clear_i, "disk rotate must come after clear in fire loop")
	# 末发后：先 +1 转再收束；空匣不硬对齐 start_index（否则红圈跳仓）
	assert_true(anim.contains("_wheel_visual_steps + 1.0"), "last shot still rotates +1 step")
	assert_true(anim.contains("not state.magazine.is_empty()"), "end align skipped when mag empty")
	assert_true(
		anim.contains("_clear_fire_flash()\n\tif state.magazine != null and not state.magazine.is_empty():")
		or anim.contains("空匣保留末发后视觉落点"),
		"clear then conditional align for non-empty only",
	)
	assert_false(
		text.contains("if _firing and fired_slot == slot_i"),
		"must not keep lightened for whole _firing via last_fired_slot"
	)


func test_modal_z_above_blood_vfx() -> void:
	assert_gt(80, 41)  # sanity: constants relation documented in source
	var f := FileAccess.open("res://scripts/combat/combat_ui.gd", FileAccess.READ)
	var text := f.get_as_text()
	assert_true(text.contains("const Z_MODAL_DIMMER := 80"))
	assert_true(text.contains("const Z_MODAL_PANEL := 90"))
	assert_true(text.contains("const Z_BLOOD_DROP := 41"))
	assert_true(text.contains("drop.z_index = Z_BLOOD_DROP"))
	assert_true(text.contains("reward_panel.z_index = Z_MODAL_PANEL"))
	var sc := FileAccess.open("res://scenes/combat.tscn", FileAccess.READ)
	var st := sc.get_as_text()
	assert_true(st.contains("z_index = 80"), "Dimmer raised in scene")
	assert_true(st.contains("z_index = 90"), "Reward/Dev raised in scene")


func test_blood_shot_dir_and_caps() -> void:
	## 射击卡顿防护 + 方向规则 + 致死血浆标记（源码契约）。
	var f := FileAccess.open("res://scripts/combat/combat_ui.gd", FileAccess.READ)
	assert_not_null(f)
	var text := f.get_as_text()
	assert_true(text.contains("const BLOOD_ACTIVE_MAX"), "must cap concurrent blood drops")
	assert_true(text.contains("func _blood_acquire_rect"), "must pool blood ColorRects")
	assert_true(text.contains("func _blood_release_rect"), "must release pooled rects")
	assert_true(text.contains("var _blood_shot_dir_active"), "must gate shot-biased spray")
	assert_true(text.contains("death_plasma"), "must support death plasma burst")
	assert_true(text.contains("Vector2.from_angle"), "omni spray uses full circle")
	assert_true(text.contains("_enemy_corpse_at_cell"), "death plasma keyed off corpse")
	# 喷血朝子弹来源（飞行方向取反），不是沿弹着前进方向
	assert_true(text.contains("_blood_spray_dir = -shot_delta.normalized()"), "spray toward bullet source")
	assert_true(text.contains("const BLOOD_BURST_MIN := 8"), "hit burst min raised")
	assert_true(text.contains("const BLOOD_DEATH_BURST_MAX := 56"), "death plasma max raised")
	assert_true(text.contains("const BLOOD_ACTIVE_MAX := 96"), "active cap raised carefully")
	# 默认不应再把无来源扣血硬编成向右喷
	assert_false(text.contains("dir = Vector2(1.0, -0.2)"), "no false rightward default spray")


func test_shot_head_keeps_ammo_hue_not_black_or_whitewash() -> void:
	## 空枪口打愤怒：芯须可读红（lightened，非暗芯）；避免纯白高光洗傲慢；描边仍吃开火前枪口。
	var f := FileAccess.open("res://scripts/combat/combat_ui.gd", FileAccess.READ)
	assert_not_null(f)
	var text := f.get_as_text()
	assert_true(text.contains("func _shot_head_display_color"), "must have hue-preserving head color helper")
	assert_true(text.contains("core.lightened(lighten_amount)"), "head uses Color.lightened")
	assert_true(text.contains("_shot_head_display_color(core_col, 0.38, 1.0)"), "core lightened enough to read dark ammo")
	assert_false(text.contains("core_col.r * 1.08 + 0.06"), "must not keep v0.2.72 weak boost that blacks wrath")
	assert_false(
		text.contains("Color(1.0, 1.0, 1.0, 0.95)"),
		"must not restore pure-white head_hot wash"
	)
	assert_true(text.contains("last_shot_muzzle_outline_ids"), "outline still from prefire muzzle ids")


func test_shot_bullet_tip_and_outer_glow_follows_outline() -> void:
	## 弹头形钝圆头（非圆 orb、非针尖）；有描边时最外辉光用 outline_cols[0]；无描边仍芯色；芯带仍弹药色。
	var f := FileAccess.open("res://scripts/combat/combat_ui.gd", FileAccess.READ)
	assert_not_null(f)
	var text := f.get_as_text()
	assert_true(text.contains("func _make_shot_bullet_tip"), "must build bullet-tip polygon")
	assert_false(text.contains("func _make_shot_orb"), "circular orb head must be removed")
	assert_true(text.contains("nose_r"), "rounded tip uses nose radius")
	assert_true(text.contains("arc_n"), "rounded tip samples nose arc")
	assert_true(text.contains("cos(ang)"), "nose arc uses cos sampling")
	assert_false(text.contains("tip_x: float = length * 0.58"), "must not keep sharp single-point tip")
	var anim_i := text.find("func _animate_shot_projectile")
	assert_gt(anim_i, 0)
	var anim_end := text.find("\nfunc ", anim_i + 10)
	var anim := text.substr(anim_i, anim_end - anim_i)
	assert_true(anim.contains("glow_col = outline_cols[0]"), "outer glow uses outermost outline when present")
	assert_true(anim.contains("var glow_col: Color = core_col"), "empty muzzle glow falls back to ammo core")
	assert_true(anim.contains("_make_shot_bullet_tip("), "projectile head uses bullet tip")
	assert_true(anim.contains("_shot_head_display_color(glow_col"), "soft outer head glow follows glow_col")
	assert_true(anim.contains("_shot_head_display_color(core_col, 0.38, 1.0)"), "core tip still ammo-colored")
	assert_true(anim.contains("Color(core_col.r, core_col.g, core_col.b, 1.0)"), "core trail band still ammo-colored")
