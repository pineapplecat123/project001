extends GutTest

const MainScene := preload("res://scenes/main.tscn")


func test_sanity() -> void:
	assert_eq(1 + 1, 2, "math works")


func test_main_scene_shows_title() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	assert_eq(main.get_title(), "project001")
	assert_eq(main.get_node("TitleLabel").text, "project001")
