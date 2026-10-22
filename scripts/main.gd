extends Control
## 主菜单：开始冒险（地图）/ 练习战斗 / 退出；底部版本号。

const VERSION := "0.2.6"


func _ready() -> void:
	%VersionLabel.text = "v%s" % VERSION
	_style_menu()


func _style_menu() -> void:
	%BtnStart.custom_minimum_size = Vector2(220, 48)
	%BtnPractice.custom_minimum_size = Vector2(220, 44)
	%BtnQuit.custom_minimum_size = Vector2(220, 40)
	%TitleLabel.add_theme_font_size_override("font_size", 52)
	%Subtitle.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	%HintLabel.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	%VersionLabel.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))


func _on_start_pressed() -> void:
	RunState.begin_run()
	get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_practice_pressed() -> void:
	RunState.end_run()
	get_tree().change_scene_to_file("res://scenes/combat.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func get_title() -> String:
	return "project001"
