extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var f := File.new()
	f.open("res://.build/typetest.log", File.WRITE)
	var ok1 := "yes"
	var s = null
	var err = false
# test Sprite2D visibility at runtime
	if ClassDB.class_exists("Sprite2D"):
		ok1 = "classdb-yes"
	else:
		ok1 = "classdb-no"
	s = null
	f.store_string("classdb=" + ok1 + "\n")
	var script := "extends Node2D\nfunc get_t():\n\treturn Sprite2D.new()\n"
	var sd := GDScript.new()
	sd.set_source_code(script)
	sd.reload()
	if sd.can_reload() or true:
		var inst = sd.new()
		if inst == null:
			f.store_string("inst=null\n")
		else:
			f.store_string("inst ok\n")
	var r = sd.reload()
	f.store_string("reload err=" + str(r) + "\n")
	f.close()
	quit(0)
