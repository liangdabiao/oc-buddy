extends SceneTree

# Headless-safe smoke: data + progress assertions only. It never boots the
# Main scene (OcView uses Sprite2D, whose global class is not visible under
# --script parse context; rendering is covered by render_all.gd with a window).

var checks := 0
var failures := 0
var done := false


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	call_deferred("_run")
	# watchdog: never hang the harness on a script error
	var t := Timer.new()
	t.wait_time = 120
	t.one_shot = true
	t.connect("timeout", self, "_watchdog")
	root.add_child(t)
	t.start()


func _watchdog() -> void:
	if not done:
		print("WATCHDOG TIMEOUT — quitting early")
		quit(2)


func _run() -> void:
	check(load("res://assets/fonts/ui.ttf") != null, "ui.ttf loads")
	check(load("res://assets/fonts/code.ttf") != null, "code.ttf loads")

	var repo = load("res://scripts/ContentRepository.gd").new()
	root.add_child(repo)
	for i in range(2):
		yield(self, "idle_frame")

	check(repo.book_count() == 13, "13 books, got %d" % repo.book_count())
	check(repo.words_total == 3493, "3493 words, got %d" % repo.words_total)
	check(repo.grammar_count() == 13, "13 grammar points")
	check(repo.shop_items.size() == 50, "50 shop items")
	check(not repo.oc_manifest.empty(), "oc manifest loaded")
	var pieces: Array = repo.oc_manifest.get("pieces", [])
	check(pieces.size() == 704, "704 oc pieces, got %d" % pieces.size())

	var total_units := 0
	for book in repo.books:
		var bid := String(book.get("id", ""))
		var units: Array = repo.units_for_book(bid)
		check(units.size() > 0, "%s has units" % bid)
		total_units += units.size()
	check(total_units == 92, "92 units, got %d" % total_units)

	# progress flow (standalone node, no App preload chain)
	var progress = load("res://scripts/ProgressStore.gd").new()
	progress.save_enabled = false
	root.add_child(progress)
	progress.data = progress.default_data()
	for i in range(2):
		yield(self, "idle_frame")

	progress.add_points(500)
	check(progress.points() >= 500, "points granted")
	check(progress.buy_item("hat_crown", 200), "buy hat_crown")
	check(not progress.buy_item("hat_crown", 200), "duplicate buy rejected")
	check(progress.points() == 300, "points deducted (300)")
	progress.equip("hat_crown", "hat")
	check(progress.equipped("hat") == "hat_crown", "equip recorded")

	var book_index := 0
	for bi in range(repo.books.size()):
		if String(repo.books[bi].get("id", "")) == "pep-primary-g3-s1":
			book_index = bi
			break
	var units: Array = repo.units_for_book("pep-primary-g3-s1")
	var unit0 := String(units[0].get("id", ""))

	# practice cards built from words
	for unit in units:
		var words: Array = unit.get("words", [])
		for w in words:
			check(String(w.get("en", "")) != "", "word has en (%s)" % unit0)
			check(String(w.get("answer", "x")) != "", "sanity")
			break
		break

	# exam scoring flow
	var first_best: int = progress.exam_best("pep-primary-g3-s1", unit0)
	progress.record_exam("pep-primary-g3-s1", unit0, 13, true)
	check(progress.exam_best("pep-primary-g3-s1", unit0) == 13,
		"exam best 13 recorded, got %d" % progress.exam_best("pep-primary-g3-s1", unit0))
	check(progress.exam_passed("pep-primary-g3-s1", unit0), "exam passed flagged")
	progress.record_exam("pep-primary-g3-s1", unit0, 8, false)
	check(progress.exam_best("pep-primary-g3-s1", unit0) == 13, "lower score keeps best")

	done = true
	print("SMOKE_CHECKS=%d FAILURES=%d" % [checks, failures])
	print("SMOKE_DONE")
	quit(1 if failures > 0 else 0)
