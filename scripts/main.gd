extends Control
## 主菜单：开始战斗 / 退出；底部版本号。无地图。

const VERSION := "0.1.1-font"


func _ready() -> void:
	%VersionLabel.text = "v%s" % VERSION


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/combat.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func get_title() -> String:
	return "project001"
