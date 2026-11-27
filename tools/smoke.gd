extends SceneTree

var checks := 0
var failures := 0


func dlog(msg: String) -> void:
	var f := File.new()
	f.open("res://.build/smoke.log", File.READ_WRITE)
	f.seek_end()
	f.store_string(msg)
	f.close()


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var f0 := File.new()
	f0.open("res://.build/smoke.log", File.WRITE)
	f0.close()
	dlog("start")
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

	# every book: units + words + per-unit practice cards buildable
	dlog("booting app")
	var main = load("res://scenes/Main.tscn").instance()
	root.add_child(main)
	for i in range(2):
		yield(self, "idle_frame")
	dlog("booted screen=%s" % main.screen)
	check(main.screen == "home", "boots to home")

	var total_units := 0
	for book in repo.books:
		var bid := String(book.get("id", ""))
		var units: Array = repo.units_for_book(bid)
		check(units.size() > 0, "%s has units" % bid)
		total_units += units.size()
		var uidx := 0
		for unit in units:
			uidx += 1
			if uidx % 5 == 0:
				dlog("  cards %s #%d" % [bid, uidx])
			var cards: Array = main._build_cards(unit.get("words", []))
			check(cards.size() == (unit.get("words", []) as Array).size() * 2,
				"cards = 2x words (%s)" % unit.get("id"))
	check(total_units == 92, "92 units, got %d" % total_units)

	# progress flow: buy -> equip -> learn -> exam points
	main.progress.add_points(500)
	check(main.progress.points() >= 500, "points granted")
	check(main.progress.buy_item("hat_crown", 200), "buy hat_crown")
	check(not main.progress.buy_item("hat_crown", 200), "duplicate buy rejected")
	check(main.progress.points() == 300, "points deducted (300), got %d" % main.progress.points())
	main.progress.equip("hat_crown", "hat")
	check(main.progress.equipped("hat") == "hat_crown", "equip recorded")

	dlog("wardrobe test")
	# OC view: open wardrobe renders layered OC
	main._open_unit("u01")
	main._show_wardrobe()
	check(main.oc_view != null and is_instance_valid(main.oc_view), "oc view alive")
	check((main.oc_view.sprites as Dictionary).size() >= 17, "sprite slots present")
	main._show_face()
	check(main.screen == "face", "face editor opens")
	main._cycle_face("hair", 8, 1)
	check(int(main.progress.oc_cfg().get("hair", 0)) == 1, "hair cycle updates cfg")

	dlog("exam flow")
	# exam flow
	var units: Array = repo.units_for_book("pep-primary-g3-s1")
	main._open_unit(String(units[0].get("id", "")))
	main._start_exam()
	check(main.screen == "exam" and main.exam_cards.size() == 15, "exam starts with 15 cards")
	main.exam_correct = 13
	main._finish_exam()
	check(main.progress.exam_best("pep-primary-g3-s1", String(units[0].get("id", ""))) == 13,
		"exam best recorded")

	print("SMOKE_CHECKS=%d FAILURES=%d" % [checks, failures])
	print("SMOKE_DONE")
	quit(1 if failures > 0 else 0)
