extends GutTest
## 版本号单一来源：GameVersion.STRING；禁止 UI 脚本再定义 const VERSION。


func test_game_version_string_nonempty() -> void:
	assert_true(GameVersion.STRING.length() > 0, "GameVersion.STRING must be non-empty")
	assert_true(GameVersion.STRING.contains("."), "GameVersion.STRING should look like semver")


func test_main_scene_uses_game_version() -> void:
	var MainScene := load("res://scenes/main.tscn")
	var main = add_child_autofree(MainScene.instantiate())
	assert_eq(main.get_node("%VersionLabel").text, "v%s" % GameVersion.STRING)


func test_no_duplicate_version_const_in_ui_scripts() -> void:
	var paths := [
		"res://scripts/main.gd",
		"res://scripts/map/map_ui.gd",
		"res://scripts/combat/combat_ui.gd",
	]
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "open %s" % path)
		var text := f.get_as_text()
		assert_false(text.contains("const VERSION"), "%s must not redefine const VERSION" % path)
		assert_true(text.contains("GameVersion.STRING"), "%s must use GameVersion.STRING" % path)
