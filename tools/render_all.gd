extends SceneTree

# Windowed visual capture for oc-buddy.

func _capture(name: String) -> void:
	for i in range(3):
		yield(self, "idle_frame")
	var image: Image = root.get_texture().get_data()
	image.flip_y()
	image.save_png("res://.build/screenshots/%s.png" % name)
	print("CAPTURED ", name)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dir := Directory.new()
	dir.make_dir_recursive("res://.build/screenshots")
	var main = load("res://scenes/Main.tscn").instance()
	root.add_child(main)
	for i in range(2):
		yield(self, "idle_frame")

	yield(_capture("home"), "completed")

	var books: Array = main.repo.books_for_track if main.repo.has_method("books_for_track") else main.repo.books
	main._show_books()
	yield(_capture("books"), "completed")

	var units: Array = main.repo.units_for_book(String(main.repo.books[0].get("id", "")))
	main.current_unit_index = 0
	main._show_lesson()
	yield(_capture("lesson"), "completed")

	main._start_practice()
	yield(_capture("practice_meaning"), "completed")

	# walk to a listening card
	main.practice_index += 1
	main._show_practice()
	yield(_capture("practice_listening"), "completed")

	main._start_exam()
	yield(_capture("exam"), "completed")

	main._show_wardrobe()
	yield(_capture("wardrobe"), "completed")

	main._show_face()
	main._cycle_face("hair", 8, 1)
	yield(_capture("face"), "completed")

	main._show_shop()
	yield(_capture("shop"), "completed")

	main._show_settings()
	yield(_capture("settings"), "completed")
	print("RENDER_DONE")
	quit(0)
