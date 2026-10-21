extends Node2D
## 主场景脚本。

const TITLE := "project001"

@onready var title_label: Label = $TitleLabel


func _ready() -> void:
	title_label.text = get_title()


func get_title() -> String:
	return TITLE
