extends Control
## 主菜单：开始冒险（地图）/ 练习战斗 / 更新日志 / 退出；底部版本号。

const CHANGELOG_PATH := "res://data/changelog.json"

var _changelog_open := false


func _ready() -> void:
	%VersionLabel.text = "v%s" % GameVersion.STRING
	_style_menu()
	_style_changelog_panel()
	_populate_changelog()
	_set_changelog_open(false)


func _style_menu() -> void:
	%BtnStart.custom_minimum_size = Vector2(220, 48)
	%BtnPractice.custom_minimum_size = Vector2(220, 44)
	%BtnChangelog.custom_minimum_size = Vector2(220, 44)
	%BtnQuit.custom_minimum_size = Vector2(220, 40)
	%TitleLabel.add_theme_font_size_override("font_size", 52)
	%Subtitle.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	%HintLabel.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	%VersionLabel.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))


func _style_changelog_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.18, 0.96)
	style.set_border_width_all(2)
	style.border_color = Color(0.45, 0.55, 0.75, 0.9)
	style.set_corner_radius_all(10)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	%ChangelogPanel.add_theme_stylebox_override("panel", style)


func _load_changelog_entries() -> Array:
	var text := FileAccess.get_file_as_string(CHANGELOG_PATH)
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var entries: Variant = parsed.get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return []
	return entries


func _populate_changelog() -> void:
	var list: VBoxContainer = %ChangelogList
	for c in list.get_children():
		c.queue_free()
	var entries := _load_changelog_entries()
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ver := str(entry.get("version", ""))
		var date := str(entry.get("date", ""))
		var items: Variant = entry.get("items", [])
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 4)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
		if date.is_empty():
			title.text = "v%s" % ver
		else:
			title.text = "v%s  ·  %s" % [ver, date]
		block.add_child(title)
		if typeof(items) == TYPE_ARRAY:
			for it in items:
				var line := Label.new()
				line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				line.add_theme_font_size_override("font_size", 15)
				line.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
				line.text = "· %s" % str(it)
				block.add_child(line)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		block.add_child(spacer)
		list.add_child(block)


func _set_changelog_open(open: bool) -> void:
	_changelog_open = open
	%ChangelogDimmer.visible = open
	%ChangelogPanel.visible = open
	%BtnStart.disabled = open
	%BtnPractice.disabled = open
	%BtnChangelog.disabled = open
	%BtnQuit.disabled = open


func _on_start_pressed() -> void:
	RunState.begin_run()
	get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_practice_pressed() -> void:
	RunState.end_run()
	get_tree().change_scene_to_file("res://scenes/combat.tscn")


func _on_changelog_pressed() -> void:
	_set_changelog_open(true)


func _on_changelog_close_pressed() -> void:
	_set_changelog_open(false)


func _on_changelog_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_changelog_open(false)


func _on_quit_pressed() -> void:
	get_tree().quit()


func get_title() -> String:
	return "project001"
