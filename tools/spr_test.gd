extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var s := Sprite2D.new()
	print("SPRITE2D_OK ", s != null)
	s.free()
	quit(0)
