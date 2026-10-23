extends GutTest
## 更新日志：JSON 可解析、非空、新→旧；主菜单有入口。

const MainScene := preload("res://scenes/main.tscn")
const CHANGELOG_PATH := "res://data/changelog.json"


func test_changelog_json_parseable_and_nonempty() -> void:
	var text := FileAccess.get_file_as_string(CHANGELOG_PATH)
	assert_false(text.is_empty(), "changelog.json must exist")
	var parsed: Variant = JSON.parse_string(text)
	assert_typeof(parsed, TYPE_DICTIONARY)
	var entries: Variant = parsed.get("entries", [])
	assert_typeof(entries, TYPE_ARRAY)
	assert_gt(entries.size(), 0, "entries must be non-empty")
	var first: Dictionary = entries[0]
	assert_eq(str(first.get("version", "")), GameVersion.STRING,
		"newest entry version should match GameVersion.STRING")
	var items: Variant = first.get("items", [])
	assert_typeof(items, TYPE_ARRAY)
	assert_gt(items.size(), 0, "newest entry needs at least one item")


func test_changelog_entries_newest_first() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHANGELOG_PATH))
	var entries: Array = parsed.get("entries", [])
	assert_gt(entries.size(), 1)
	for i in range(entries.size() - 1):
		var a := str(entries[i].get("version", "0"))
		var b := str(entries[i + 1].get("version", "0"))
		assert_true(_version_ge(a, b), "expected %s >= %s (newest first)" % [a, b])


func test_main_menu_has_changelog_button() -> void:
	var main = add_child_autofree(MainScene.instantiate())
	await get_tree().process_frame
	var btn: Button = main.get_node("%BtnChangelog")
	assert_not_null(btn)
	assert_eq(btn.text, "更新日志")
	assert_false(main.get_node("%ChangelogPanel").visible)
	btn.emit_signal("pressed")
	await get_tree().process_frame
	assert_true(main.get_node("%ChangelogPanel").visible)
	var list: VBoxContainer = main.get_node("%ChangelogList")
	assert_gt(list.get_child_count(), 0, "changelog list should be populated")


func _version_ge(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	var n: int = maxi(pa.size(), pb.size())
	for i in n:
		var ai := int(pa[i]) if i < pa.size() else 0
		var bi := int(pb[i]) if i < pb.size() else 0
		if ai > bi:
			return true
		if ai < bi:
			return false
	return true
