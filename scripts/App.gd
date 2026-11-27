extends Control

# OC Buddy — R36S port of 「带着OC学英语」 (upstream oc-english by yczz).
# Study English to earn points, spend them dressing up your OC.
# v1: study center (13 PEP books / 92 units / 3,493 words), practice cards
# (meaning + listening via MiMo TTS), unit exam, points economy, shop,
# wardrobe (50 items), face editor.

const MimoScript = preload("res://scripts/MimoClient.gd")
const SettingsScript = preload("res://scripts/Settings.gd")
const UIKitScript = preload("res://scripts/UIKit.gd")
const ChromeScript = preload("res://scripts/Chrome.gd")

const PAGE_SIZE := 6
const EXAM_TOTAL := 15
const EXAM_PASS := 12
const OPTION_LETTERS := "ABCDEFGH"

var ui
var repo
var progress
var mimo
var settings
var chrome: Control
var screen_root: Control
var oc_view = null

var screen := "home"
var title_text := "OC Buddy" setget _set_title_text
var footer_text := "" setget _set_footer_text
var menu_panels: Array = []
var menu_meta: Array = []
var menu_index := 0
var list_page := 0

var toast_text := ""
var toast_time := 0.0

var current_book_index := 0
var current_unit_index := 0
var practice_cards: Array = []
var practice_index := 0
var exam_cards: Array = []
var exam_index := 0
var exam_correct := 0
var exam_first := false
var current_word := {}
var _tts_cache := {}
var _player: AudioStreamPlayer = null
var tour_mode := false               # screenshot tour skips network TTS


func _ready() -> void:
	ui = UIKitScript.new()
	repo = load("res://scripts/ContentRepository.gd").new()
	progress = load("res://scripts/ProgressStore.gd").new()
	mimo = MimoScript.new()
	settings = SettingsScript.new()
	for n in [repo, progress, mimo, settings]:
		add_child(n)
	mimo.api_key = settings.api_key
	mimo.voice = "Chloe"
	mimo.connect("tts_done", self, "_on_tts_done")
	mimo.connect("request_error", self, "_on_tts_error")
	var backdrop: Panel = ui.panel(self, Rect2(0, 0, 640, 480), ui.BG, Color(0, 0, 0, 0), 0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(backdrop, 0)
	chrome = ChromeScript.new()
	chrome.app = self
	chrome.rect_size = Vector2(640, 480)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chrome)
	_show_home()
	for a in OS.get_cmdline_args():
		if a == "--screenshot-tour":
			call_deferred("_screenshot_tour")
			return


var _tour_steps: Array = []


func _tour_trace(msg: String) -> void:
	var f := File.new()
	f.open("user://tour_trace.txt", File.READ_WRITE)
	f.seek_end()
	f.store_string(msg + "|")
	f.close()


func _screenshot_tour() -> void:
	tour_mode = true
	_tour_trace("tour begin")
	_tour_steps = [
		["home", ""], ["books", "_show_books"], ["units", "_show_units"],
		["lesson", "_show_lesson"],
		["shop", "_show_shop"], ["wardrobe", "_show_wardrobe"],
		["face", "_show_face"], ["settings", "_show_settings"], ["about", "_show_about"],
	]
	_tour_next()


func _tour_next() -> void:
	if _tour_steps.empty():
		_tour_trace("tour done")
		get_tree().quit(0)
		return
	var step: Array = _tour_steps.pop_front()
	_tour_trace("step " + String(step[0]))
	var method := String(step[1])
	if method != "":
		call(method)
		_tour_trace("called " + method)
	_sync_chrome()
	for i in range(3):
		yield(get_tree(), "idle_frame")
	var image: Image = get_viewport().get_texture().get_data()
	image.flip_y()
	image.save_png("res://.build/screenshots/%s.png" % String(step[0]))
	_tour_trace("shot " + String(step[0]))
	_tour_next()


func _set_title_text(v: String) -> void:
	title_text = v
	_sync_chrome()


func _set_footer_text(v: String) -> void:
	footer_text = v
	_sync_chrome()


func _sync_chrome() -> void:
	if chrome != null and is_instance_valid(chrome):
		chrome.update()


func draw_chrome(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, 640, 54), Color(0.043, 0.063, 0.098, 0.95))
	ci.draw_rect(Rect2(0, 53, 640, 1), ui.LINE)
	ci.draw_string(ui.font(19), Vector2(20, 34), title_text, ui.TEXT)
	var status := "%d 积分 · 已学 %d/%d 课" % [progress.points(), _learned_count(), _unit_total()]
	ci.draw_string(ui.font(13), Vector2(620 - ui.font(13).get_string_size(status).x, 33), status, ui.GOLD)
	ci.draw_rect(Rect2(0, 444, 640, 36), Color(0.043, 0.063, 0.098, 0.95))
	ci.draw_rect(Rect2(0, 444, 640, 1), ui.LINE)
	ci.draw_string(ui.font(14), Vector2(20, 467), footer_text, ui.MUTED)
	if toast_text != "":
		var width: float = ui.font(17).get_string_size(toast_text).x + 40
		ci.draw_rect(Rect2((640 - width) / 2, 61, width, 38), Color(0.09, 0.14, 0.22, 0.96))
		ci.draw_string(ui.font(17), Vector2((640 - width) / 2 + 20, 86), toast_text, ui.GREEN)


func _process(delta: float) -> void:
	if toast_time > 0:
		toast_time -= delta
		if toast_time <= 0:
			toast_text = ""
			_sync_chrome()


func _show_toast(text: String) -> void:
	toast_text = text
	toast_time = 3.0
	_sync_chrome()


func _learned_count() -> int:
	var n := 0
	for book in repo.books:
		for unit in book.get("units", []):
			if progress.unit_learned(String(book.get("id", "")), String(unit.get("id", ""))):
				n += 1
	return n


func _unit_total() -> int:
	var n := 0
	for book in repo.books:
		n += (book.get("units", []) as Array).size()
	return n


# ============================================================= input =======

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey and event.echo:
		return
	var action := ""
	for candidate in ["nav_up", "nav_down", "nav_left", "nav_right", "accept", "back", "menu"]:
		if event.is_action_pressed(candidate):
			action = candidate
			break
	if action == "":
		return
	get_viewport().set_input_as_handled()
	match action:
		"nav_up": _navigate(-1)
		"nav_down": _navigate(1)
		"nav_left", "prev": _page_step(-1)
		"nav_right", "next": _page_step(1)
		"accept": _accept()
		"back": _back()
		"menu": _show_home()


func _clear_screen() -> void:
	if is_instance_valid(screen_root):
		remove_child(screen_root)
		screen_root.queue_free()
	screen_root = Control.new()
	screen_root.rect_size = Vector2(640, 480)
	screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen_root)
	move_child(screen_root, 1)
	menu_panels.clear()
	menu_meta.clear()
	menu_index = 0
	_sync_chrome()


# ============================================================= menu ========

func _build_menu(items: Array, rect: Rect2, spacing: float, columns: int) -> void:
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var y: float = rect.position.y + index * spacing
		var panel: Panel = ui.panel(screen_root, Rect2(rect.position.x, y, rect.size.x, rect.size.y), ui.PANEL, ui.LINE, 10)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.connect("gui_input", self, "_on_menu_gui_input", [index], CONNECT_DEFERRED)
		var status: String = String(item.get("status", ""))
		var status_width: float = ui.font(14).get_string_size(status).x + 8 if status != "" else 0
		ui.label(panel, String(item.get("text", "")), Rect2(16, 3, rect.size.x - status_width - 24, rect.size.y - 6), 16, ui.TEXT, 0, true)
		if status != "":
			ui.label(panel, status, Rect2(rect.size.x - status_width - 8, 3, status_width, rect.size.y - 6), 13, ui.GREEN, 2)
		if not bool(item.get("enabled", true)):
			panel.modulate = Color(1, 1, 1, 0.4)
		menu_panels.append(panel)
		menu_meta.append(item)
	_refresh_menu()


func _refresh_menu() -> void:
	for index in range(menu_panels.size()):
		var selected := index == menu_index
		menu_panels[index].add_stylebox_override("panel", ui.style(
			ui.PANEL_LIGHT if selected else ui.PANEL,
			ui.GOLD if selected else ui.LINE, 10, 2 if selected else 1))
		if bool(menu_meta[index].get("enabled", true)):
			menu_panels[index].modulate = Color(1, 1, 1, 1)


func _on_menu_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		menu_index = index
		_refresh_menu()
		_activate_menu()


func _navigate(direction: int) -> void:
	if menu_panels.empty():
		return
	if screen in ["books", "units", "shop", "wardrobe"]:
		var total: int = _list_count()
		var count: int = min(PAGE_SIZE, total - list_page * PAGE_SIZE)
		if direction < 0 and menu_index == 0 and list_page > 0:
			list_page -= 1
			_show_list()
			return
		if direction > 0 and menu_index == count - 1 and (list_page + 1) * PAGE_SIZE < total:
			list_page += 1
			_show_list()
			return
	menu_index = posmod(menu_index + direction, menu_panels.size())
	_refresh_menu()


func _list_count() -> int:
	match screen:
		"books":
			return repo.book_count()
		"units":
			return repo.units_for_book(_book_id()).size()
		"shop":
			return repo.shop_items.size()
		"wardrobe":
			return _owned_items().size()
	return 0


func _show_list() -> void:
	match screen:
		"books": _show_books()
		"units": _show_units()
		"shop": _show_shop()
		"wardrobe": _show_wardrobe()


func _page_step(direction: int) -> void:
	match screen:
		"books", "units", "shop", "wardrobe":
			var total := _list_count()
			var max_page := max(0, int(ceil(float(total) / float(PAGE_SIZE))) - 1)
			var np := clamp(list_page + direction, 0, max_page)
			if np != list_page:
				list_page = np
				_show_list()


func _accept() -> void:
	if not menu_panels.empty():
		_activate_menu()


func _back() -> void:
	match screen:
		"units": _show_books()
		"books": _show_home()
		"lesson": _show_units()
		"practice": _show_lesson()
		"exam": _show_lesson()
		"exam_result": _show_lesson()
		"shop", "wardrobe", "face", "settings", "about": _show_home()
		"home": pass


# ============================================================= home ========

func _show_home() -> void:
	_clear_screen()
	screen = "home"
	title_text = "OC Buddy"
	footer_text = "上下键 选择   A 确认   Start 退出"

	var oc := Control.new()
	oc.name = "OcHome"
	oc.rect_position = Vector2(110, 80)
	oc.rect_scale = Vector2(0.85, 0.85)
	screen_root.add_child(oc)
	var view_script: Script = load("res://scripts/OcView.gd")
	oc_view = view_script.new()
	oc_view.rect_position = Vector2.ZERO
	oc.add_child(oc_view)
	oc_view.setup(repo, progress.oc_cfg())

	ui.label(screen_root, "带着 OC 学英语", Rect2(290, 84, 320, 28), 15, ui.GREEN)
	ui.label(screen_root, "%d 积分" % progress.points(), Rect2(290, 118, 320, 44), 30, ui.GOLD)
	ui.label(screen_root, "认真学英语，是赚积分的唯一方式", Rect2(290, 170, 320, 24), 13, ui.MUTED, 0, true)
	var items := [
		{"text": "学习中心 · 13 册教材", "action": "books", "enabled": true},
		{"text": "衣橱 · 换装", "action": "wardrobe", "enabled": true},
		{"text": "捏脸工坊", "action": "face", "enabled": true},
		{"text": "商店 · 用积分换装扮", "action": "shop", "enabled": true},
		{"text": "设置", "action": "settings", "enabled": true},
		{"text": "关于", "action": "about", "enabled": true},
	]
	_build_menu(items, Rect2(290, 204, 326, 34), 40, 0)
	ui.label(screen_root, "积分只能靠学习赚取；听力题需联网（MiMo TTS）。", Rect2(44, 424, 552, 20), 12, ui.MUTED, 1)


# ====================================================== books / units ======

func _book_id() -> String:
	return String(repo.get_book(current_book_index).get("id", ""))


func _book_title() -> String:
	return String(repo.get_book(current_book_index).get("title", "")).substr(0, 22)


func _show_books() -> void:
	_clear_screen()
	screen = "books"
	title_text = "学习中心"
	footer_text = "上下键 选择   A 进入   B 首页   左右键 翻页"
	var start := list_page * PAGE_SIZE
	var items := []
	for index in range(start, min(start + PAGE_SIZE, repo.book_count())):
		var book: Dictionary = repo.get_book(index)
		var unit_list: Array = book.get("units", [])
		var done := 0
		for unit in unit_list:
			if progress.unit_learned(String(book.get("id", "")), String(unit.get("id", ""))):
				done += 1
		items.append({
			"text": String(book.get("title", "")),
			"status": "%d/%d" % [done, unit_list.size()],
			"action": "book", "index": index, "enabled": true,
		})
	_build_menu(items, Rect2(28, 72, 584, 40), 46, 0)
	var pages := max(1, int(ceil(float(repo.book_count()) / float(PAGE_SIZE))))
	ui.label(screen_root, "第 %d / %d 页" % [list_page + 1, pages], Rect2(420, 452, 192, 22), 13, ui.MUTED, 2)


func _show_units() -> void:
	_clear_screen()
	screen = "units"
	title_text = _book_title()
	footer_text = "上下键 选择   A 学习   B 返回   左右键 翻页"
	var units: Array = repo.units_for_book(_book_id())
	var grammar: Dictionary = repo.grammar_for_book(_book_id())
	var start := list_page * PAGE_SIZE
	var items := []
	items.append({"text": "语法卡 · " + String(grammar.get("title", "语法")), "action": "grammar", "enabled": true})
	for index in range(start, min(start + PAGE_SIZE, units.size())):
		var unit: Dictionary = units[index]
		var unit_id := String(unit.get("id", ""))
		var learned: bool = progress.unit_learned(_book_id(), unit_id)
		var passed: bool = progress.exam_passed(_book_id(), unit_id)
		var status := "通过" if passed else ("已学" if learned else "")
		items.append({
			"text": "Unit %d %s" % [int(unit.get("number", 0)), String(unit.get("title", ""))],
			"status": status,
			"action": "unit", "index": index, "enabled": true,
		})
	_build_menu(items, Rect2(28, 72, 584, 40), 46, 0)
	var pages := max(1, int(ceil(float(units.size()) / float(PAGE_SIZE))))
	ui.label(screen_root, "第 %d / %d 页" % [list_page + 1, pages], Rect2(420, 452, 192, 22), 13, ui.MUTED, 2)


func _show_lesson() -> void:
	_clear_screen()
	screen = "lesson"
	var units: Array = repo.units_for_book(_book_id())
	var unit: Dictionary = units[current_unit_index] if current_unit_index < units.size() else {}
	var words: Array = unit.get("words", [])
	title_text = ("Unit %d %s" % [int(unit.get("number", 0)), String(unit.get("title", ""))]).substr(0, 22)
	footer_text = "A 翻页   X 开始跟练   Y 单元考   B 返回"
	var grammar: Dictionary = repo.grammar_for_book(_book_id())
	var y := 68.0
	ui.label(screen_root, "语法卡 · " + String(grammar.get("title", "")), Rect2(28, y, 584, 24), 15, ui.GOLD)
	y += 30.0
	ui.label(screen_root, String(grammar.get("explain", "")), Rect2(28, y, 584, 84), 15, ui.TEXT, 0, true)
	y += 96.0
	ui.label(screen_root, "单词表（%d 词）" % words.size(), Rect2(28, y, 584, 24), 15, ui.GOLD)
	y += 30.0
	for index in range(words.size()):
		var word: Dictionary = words[index]
		var col := index % 2
		var row: int = index / 2
		var x := 28.0 + col * 300.0
		var wy := y + row * 42.0
		if wy > 402.0:
			ui.label(screen_root, "…", Rect2(x, wy, 288, 24), 14, ui.MUTED)
			break
		ui.panel(screen_root, Rect2(x, wy, 288, 38), ui.PANEL, ui.LINE, 8)
		ui.label(screen_root, String(word.get("en", "")), Rect2(x + 10, wy + 2, 130, 34), 16, ui.BLUE)
		ui.label(screen_root, String(word.get("zh", "")).substr(0, 16), Rect2(x + 140, wy + 2, 140, 34), 12, ui.MUTED, 0, true)


# ====================================================== practice / exam ====

func _start_practice() -> void:
	var unit := _current_unit()
	var words: Array = unit.get("words", [])
	practice_cards = _build_cards(words)
	practice_index = 0
	screen = "practice"
	_show_practice()


func _current_unit() -> Dictionary:
	var units: Array = repo.units_for_book(_book_id())
	if current_unit_index < units.size():
		return units[current_unit_index]
	return {}


func _build_cards(words: Array) -> Array:
	var cards: Array = []
	for word in words:
		var others := _pick_others(words, word, 3)
		var meaning_opts := [word.zh]
		for o in others:
			meaning_opts.append(o.zh)
		meaning_opts.shuffle()
		cards.append({"kind": "meaning", "word": word, "options": meaning_opts, "answer": word.zh})
		var listen_opts := [word.en]
		for o in others:
			listen_opts.append(o.en)
		listen_opts.shuffle()
		cards.append({"kind": "listening", "word": word, "options": listen_opts, "answer": word.en})
	return cards


func _pick_others(words: Array, except: Dictionary, n: int) -> Array:
	var out: Array = []
	var copy := words.duplicate()
	copy.shuffle()
	for w in copy:
		if String(w.get("en", "")) != String(except.get("en", "")) and out.size() < n:
			out.append(w)
	return out


func _show_practice() -> void:
	_clear_screen()
	screen = "practice"
	title_text = "跟练"
	footer_text = "上下键 选择   A 确认"
	if practice_index >= practice_cards.size():
		var unit: Dictionary = _current_unit()
		progress.mark_word_learned(_book_id(), String(unit.get("id", "")))
		progress.add_card_points()
		_show_toast("跟练完成！解锁单元考")
		_show_lesson()
		return
	var card: Dictionary = practice_cards[practice_index]
	current_word = card.get("word", {})
	var kind := String(card.get("kind", ""))
	ui.label(screen_root, "跟练 %d/%d · %s" % [practice_index + 1, practice_cards.size(), "词义" if kind == "meaning" else "听力"], Rect2(28, 62, 584, 24), 14, ui.GOLD, 2)
	if kind == "meaning":
		ui.label(screen_root, String(card.get("word", {}).get("en", "")), Rect2(40, 104, 560, 60), 30, ui.BLUE)
		var phonetic := String(card.get("word", {}).get("phonetic", ""))
		if phonetic != "":
			ui.label(screen_root, phonetic, Rect2(40, 164, 560, 30), 15, ui.MUTED, 0, false, ui.code_font(15))
	else:
		ui.label(screen_root, "听音频，选出你听到的单词", Rect2(40, 110, 560, 40), 19, ui.TEXT)
		var play: Panel = ui.panel(screen_root, Rect2(280, 156, 90, 34), ui.PANEL_LIGHT, ui.GOLD, 17)
		play.mouse_filter = Control.MOUSE_FILTER_STOP
		play.connect("gui_input", self, "_on_play_gui_input", [], CONNECT_DEFERRED)
		ui.label(play, "播放", Rect2(0, 7, 90, 22), 14, ui.GOLD, 1)
		_tts_word(String(card.get("word", {}).get("en", "")))
	_build_option_menu(card.get("options", []))


func _build_option_menu(options: Array) -> void:
	var items := []
	for index in range(options.size()):
		items.append({"text": "%s. %s" % [OPTION_LETTERS.substr(index, 1), String(options[index])],
			"action": "option", "index": index, "enabled": true})
	_build_menu(items, Rect2(44, 216, 552, 44), 50, 0)


func _on_play_gui_input(_event: InputEvent) -> void:
	_tts_word(String(current_word.get("en", "")))




func _tts_word(word: String) -> void:
	if tour_mode:
		return
	var key := word.to_lower()
	if _tts_cache.has(key):
		_play_stream(_tts_cache[key])
		return
	if settings.api_key == "":
		_show_toast("听力需要 MiMo API Key")
		return
	var dir := Directory.new()
	dir.make_dir_recursive("user://tts_cache")
	mimo.tts(word, settings.style_hint)




func _on_tts_done(stream) -> void:
	_tts_cache[String(current_word.get("en", "")).to_lower()] = stream
	_play_stream(stream)


func _on_tts_error(msg: String) -> void:
	_show_toast(msg)


func _play_stream(stream) -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	add_child(_player)
	_player.play()


func _answer(index: int) -> void:
	var card: Dictionary = practice_cards[practice_index] if screen == "practice" else exam_cards[exam_index]
	var options: Array = card.get("options", [])
	var correct: bool = index >= 0 and index < options.size() and String(options[index]) == String(card.get("answer", ""))
	if screen == "practice":
		if correct:
			progress.add_card_points()
			_show_toast("答对 +2 积分")
			practice_index += 1
			_show_practice()
		else:
			_show_toast("再想想")
	else:
		if correct:
			exam_correct += 1
		exam_index += 1
		if exam_index >= exam_cards.size():
			_finish_exam()
		else:
			_show_exam()


func _start_exam() -> void:
	var unit := _current_unit()
	var words: Array = unit.get("words", [])
	var cards := _build_cards(words)
	cards.shuffle()
	exam_cards = cards.slice(0, min(EXAM_TOTAL, cards.size()) - 1)
	exam_index = 0
	exam_correct = 0
	var unit_id := String(unit.get("id", ""))
	exam_first = not progress.exam_passed(_book_id(), unit_id)
	screen = "exam"
	_show_exam()


func _show_exam() -> void:
	_clear_screen()
	screen = "exam"
	title_text = "单元考"
	footer_text = "上下键 选择   A 确认"
	if exam_index >= exam_cards.size():
		_finish_exam()
		return
	var card: Dictionary = exam_cards[exam_index]
	current_word = card.get("word", {})
	var kind := String(card.get("kind", ""))
	ui.label(screen_root, "第 %d / %d 题 · %s" % [exam_index + 1, exam_cards.size(), "词义" if kind == "meaning" else "听力"], Rect2(28, 62, 584, 24), 14, ui.GOLD, 2)
	if kind == "meaning":
		ui.label(screen_root, String(card.get("word", {}).get("en", "")), Rect2(40, 104, 560, 60), 30, ui.BLUE)
		var phonetic := String(card.get("word", {}).get("phonetic", ""))
		if phonetic != "":
			ui.label(screen_root, phonetic, Rect2(40, 164, 560, 30), 15, ui.MUTED, 0, false, ui.code_font(15))
	else:
		ui.label(screen_root, "听音频选词", Rect2(40, 110, 560, 40), 19, ui.TEXT)
		var play: Panel = ui.panel(screen_root, Rect2(280, 156, 90, 34), ui.PANEL_LIGHT, ui.GOLD, 17)
		play.mouse_filter = Control.MOUSE_FILTER_STOP
		play.connect("gui_input", self, "_on_play_gui_input", [], CONNECT_DEFERRED)
		ui.label(play, "播放", Rect2(0, 7, 90, 22), 14, ui.GOLD, 1)
		_tts_word(String(card.get("word", {}).get("en", "")))
	_build_option_menu(card.get("options", []))


func _finish_exam() -> void:
	var unit := _current_unit()
	var unit_id := String(unit.get("id", ""))
	var bonus: int = progress.record_exam(_book_id(), unit_id, exam_correct, exam_first)
	_clear_screen()
	screen = "exam_result"
	title_text = "单元考成绩"
	footer_text = "A 确认   B 返回"
	var passed := exam_correct >= EXAM_PASS
	ui.label(screen_root, "%d / %d" % [exam_correct, exam_cards.size()], Rect2(40, 110, 300, 60), 38, ui.GOLD if passed else ui.RED)
	ui.label(screen_root, "通过线 %d 题" % EXAM_PASS, Rect2(340, 122, 260, 40), 18, ui.MUTED)
	var verdict := "通过！" if passed else "未通过，继续跟练后再考。"
	ui.label(screen_root, verdict, Rect2(40, 180, 560, 30), 16, ui.GREEN if passed else ui.MUTED)
	if bonus > 0:
		ui.label(screen_root, "积分 +%d" % bonus, Rect2(40, 214, 560, 30), 17, ui.GOLD)
	var items := [
		{"text": "重新考试", "action": "exam_retry", "enabled": true},
		{"text": "回到课表", "action": "units", "enabled": true},
		{"text": "回到首页", "action": "home", "enabled": true},
	]
	_build_menu(items, Rect2(180, 260, 360, 40), 46, 0)


# ====================================================== shop / wardrobe ==== 

func _owned_items() -> Array:
	var out: Array = []
	for item in repo.shop_items:
		if progress.owns(String(item.get("id", ""))):
			out.append(item)
	return out


func _show_shop() -> void:
	_clear_screen()
	screen = "shop"
	title_text = "商店 · %d 积分" % progress.points()
	footer_text = "上下键 选择   A 购买   B 返回   左右键 翻页"
	var items_all: Array = repo.shop_items
	var start := list_page * PAGE_SIZE
	var items := []
	for index in range(start, min(start + PAGE_SIZE, items_all.size())):
		var item: Dictionary = items_all[index]
		var item_id := String(item.get("id", ""))
		var owned: bool = progress.owns(item_id)
		var price: int = int(item.get("price", 0))
		items.append({
			"text": "%s [%s]" % [String(item.get("name", "")), String(item.get("slot", ""))],
			"status": "已拥有" if owned else "%d 积分" % price,
			"action": "buy", "item": item_id, "price": price,
			"enabled": not owned,
		})
	_build_menu(items, Rect2(28, 72, 584, 40), 46, 0)
	var pages := max(1, int(ceil(float(items_all.size()) / float(PAGE_SIZE))))
	ui.label(screen_root, "第 %d / %d 页" % [list_page + 1, pages], Rect2(420, 452, 192, 22), 13, ui.MUTED, 2)


func _show_wardrobe() -> void:
	_clear_screen()
	screen = "wardrobe"
	title_text = "衣橱"
	footer_text = "上下键 选择   A 穿上/脱下   B 返回   左右键 翻页"

	var oc := Control.new()
	oc.rect_position = Vector2(100, 66)
	oc.rect_scale = Vector2(0.8, 0.8)
	screen_root.add_child(oc)
	var view_script: Script = load("res://scripts/OcView.gd")
	oc_view = view_script.new()
	oc.add_child(oc_view)
	oc_view.setup(repo, progress.oc_cfg())

	var owned: Array = _owned_items()
	var start := list_page * PAGE_SIZE
	var items := []
	for index in range(start, min(start + PAGE_SIZE, owned.size())):
		var item: Dictionary = owned[index]
		var slot := String(item.get("slot", ""))
		var equipped: bool = progress.equipped(slot) == String(item.get("id", ""))
		items.append({
			"text": "%s [%s]" % [String(item.get("name", "")), slot],
			"status": "穿着中" if equipped else "",
			"action": "wear", "item": String(item.get("id", "")), "slot": slot,
			"enabled": true,
		})
	_build_menu(items, Rect2(300, 60, 316, 38), 44, 0)
	var pages := max(1, int(ceil(float(owned.size()) / float(PAGE_SIZE))))
	ui.label(screen_root, "第 %d / %d 页" % [list_page + 1, pages], Rect2(300, 452, 192, 22), 13, ui.MUTED, 2)


func _show_face() -> void:
	_clear_screen()
	screen = "face"
	title_text = "捏脸工坊 · 免费"
	footer_text = "上下键 选择项目   A/点击 更换   B 返回"

	var oc := Control.new()
	oc.rect_position = Vector2(100, 66)
	oc.rect_scale = Vector2(0.8, 0.8)
	screen_root.add_child(oc)
	var view_script: Script = load("res://scripts/OcView.gd")
	oc_view = view_script.new()
	oc.add_child(oc_view)
	oc_view.setup(repo, progress.oc_cfg())

	var cfg: Dictionary = progress.oc_cfg()
	var rows := [
		{"key": "skin", "label": "肤色", "count": 4},
		{"key": "hair", "label": "发型", "count": 8},
		{"key": "hairColor", "label": "发色", "count": 8},
		{"key": "eyes", "label": "眼型", "count": 6},
		{"key": "eyeColor", "label": "瞳色", "count": 6},
		{"key": "mouth", "label": "嘴巴", "count": 5},
		{"key": "showBlush", "label": "腮红", "count": 2},
	]
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var key := String(row["key"])
		var count := int(row["count"])
		var current: int = int(cfg.get(key, 0)) if key != "showBlush" else (1 if bool(cfg.get(key, true)) else 0)
		var y := 80.0 + index * 46.0
		var panel: Panel = ui.panel(screen_root, Rect2(300, y, 316, 40), ui.PANEL, ui.LINE, 8)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.connect("gui_input", self, "_on_face_gui_input", [key, count], CONNECT_DEFERRED)
		ui.label(panel, String(row["label"]), Rect2(16, 8, 80, 26), 15, ui.GOLD)
		var value_text := ("开" if current == 1 else "关") if key == "showBlush" else "%d / %d" % [current + 1, count]
		ui.label(panel, "<  " + value_text + "  >", Rect2(110, 8, 190, 26), 15, ui.TEXT, 1)
	ui.label(screen_root, "点击一行或按 A 更换样式（即时预览）", Rect2(300, 380, 316, 40), 12, ui.MUTED, 0, true)


func _cycle_face(key: String, count: int, direction: int) -> void:
	if key == "showBlush":
		progress.set_oc_slot("showBlush", not bool(progress.oc_cfg().get("showBlush", true)))
	else:
		var current: int = int(progress.oc_cfg().get(key, 0))
		progress.set_oc_slot(key, posmod(current + direction, count))
	if oc_view != null and is_instance_valid(oc_view):
		oc_view.cfg = progress.oc_cfg().duplicate(true)
		oc_view.refresh()


func _on_face_gui_input(event: InputEvent, key: String, count: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		_cycle_face(key, count, 1)


# ====================================================== settings / about ===

func _show_settings() -> void:
	_clear_screen()
	screen = "settings"
	title_text = "设置"
	footer_text = "B 返回首页"
	var masked := "未设置" if not settings.has_key() else ("%s…%s" % [settings.api_key.substr(0, 5), settings.api_key.substr(settings.api_key.length() - 4)])
	var rows := [
		["MiMo API Key", masked],
		["听力 TTS 音色", settings.voice],
		["说明", "Key 在 settings.local.json（开发）或 user://oc_buddy_settings.json 配置；听力题需联网调用 MiMo 云 TTS。"],
	]
	for index in range(rows.size()):
		var y := 90 + index * 84
		ui.label(screen_root, rows[index][0], Rect2(48, y, 300, 40), 16, ui.GOLD)
		ui.label(screen_root, rows[index][1], Rect2(48, y + 30, 544, 50), 14, ui.TEXT, 0, true)


func _show_about() -> void:
	_clear_screen()
	screen = "about"
	title_text = "关于"
	footer_text = "B 返回"
	ui.label(screen_root, "OC Buddy · 带着OC学英语（R36S 版）", Rect2(48, 80, 544, 34), 22, ui.GOLD)
	ui.label(screen_root, "课程与玩法参考开源项目 oc-english（yczz）。\n积分只能靠学习赚取；听力题需联网调用 MiMo TTS。\n内容仅供个人学习使用。", Rect2(48, 130, 544, 160), 15, ui.TEXT, 0, true)
	ui.label(screen_root, "收录：%d 册 %d 单元 %d 词 · %d 件装扮" % [repo.book_count(), _unit_total(), repo.words_total, repo.shop_items.size()], Rect2(48, 300, 544, 34), 14, ui.MUTED)


# ====================================================== dispatch ===========

func _activate_menu() -> void:
	if menu_index < 0 or menu_index >= menu_meta.size():
		return
	var item: Dictionary = menu_meta[menu_index]
	if not bool(item.get("enabled", true)):
		return
	match String(item.get("action", "")):
		"option": _answer(int(item.get("index", 0)))
		"books": _show_books()
		"book":
			current_book_index = int(item.get("index", 0))
			list_page = 0
			_show_units()
		"unit":
			current_unit_index = int(item.get("index", 0))
			list_page = 0
			_show_lesson()
		"grammar": _show_lesson()
		"practice_start": _start_practice()
		"exam_start": _start_exam()
		"exam_retry": _start_exam()
		"units": _show_units()
		"wardrobe": _show_wardrobe()
		"face": _show_face()
		"shop": _show_shop()
		"settings": _show_settings()
		"about": _show_about()
		"wear":
			var item_id := String(item.get("item", ""))
			var slot := String(item.get("slot", ""))
			if progress.equipped(slot) == item_id:
				progress.unequip(slot)
				_show_toast("已脱下")
			else:
				progress.equip(item_id, slot)
				_show_toast("已穿上")
			_show_wardrobe()
		"buy":
			var item_id := String(item.get("item", ""))
			var price := int(item.get("price", 0))
			if progress.buy_item(item_id, price):
				_show_toast("购买成功！去衣橱换装")
			else:
				_show_toast("积分不足（需要 %d）" % price)
			_show_shop()
		"home": _show_home()
