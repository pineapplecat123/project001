extends GutTest
## 击发白蒙版：转盘前必须 clear，不得靠 last_fired_slot 整段射击加亮。


func test_fire_overlay_cleared_before_disk_rotate() -> void:
	var f := FileAccess.open("res://scripts/combat/combat_ui.gd", FileAccess.READ)
	assert_not_null(f)
	var text := f.get_as_text()
	assert_true(text.contains("var _fire_overlay_slot"), "must track overlay slot locally")
	assert_true(text.contains("func _clear_fire_overlay"), "must have clear helper")
	assert_true(text.contains("func _begin_fire_overlay"), "must have begin helper")
	var anim_i := text.find("func _animate_fire_shots")
	assert_gt(anim_i, 0)
	var anim := text.substr(anim_i, text.find("\nfunc ", anim_i + 10) - anim_i)
	var hold_i := anim.find("FIRE_FLASH_HOLD")
	assert_gt(hold_i, 0, "fire loop must await FIRE_FLASH_HOLD")
	var after_hold := anim.substr(hold_i, 280)
	assert_true(after_hold.contains("_clear_fire_overlay()"), "clear overlay right after flash hold")
	var clear_i := anim.find("_clear_fire_overlay()", hold_i)
	var rotate_i := anim.find("_animate_disk_to", clear_i)
	assert_gt(rotate_i, clear_i, "disk rotate must come after clear in fire loop")
	assert_true(anim.contains("_clear_fire_overlay()\n\t_apply_disk_rotation"), "clear before end snap align")
	assert_true(text.contains("overlay_slot == slot_i"), "paint highlights via overlay_slot")
	assert_false(
		text.contains("if _firing and fired_slot == slot_i"),
		"must not keep lightened for whole _firing via last_fired_slot"
	)
