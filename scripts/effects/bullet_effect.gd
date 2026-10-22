class_name BulletEffect
## 弹药效果接口。


func ammo_id() -> int:
	return -1


func compute_damage(_ctx: Dictionary) -> int:
	return 0


func on_fire(_ctx: Dictionary) -> void:
	pass
