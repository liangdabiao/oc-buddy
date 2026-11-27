extends Node

signal changed

const SAVE_PATH := "user://oc_buddy_profile.json"
const BACKUP_PATH := "user://oc_buddy_profile.bak"
const TEMP_PATH := "user://oc_buddy_profile.tmp"

const EXAM_PASS := 12          # out of 15, mirroring upstream
const BONUS_NEWBIE := 200
const BONUS_CARD := 2
const BONUS_EXAM_FIRST := 100
const BONUS_EXAM_IMPROVE := 10

var data: Dictionary = default_data()


func _ready() -> void:
	load_game()


func default_data() -> Dictionary:
	return {
		"version": 1,
		"points": 0,
		"newbieGiven": false,
		"owned": {},          # item id -> true
		"oc": {"skin": 0, "hair": 0, "hairColor": 0, "eyes": 0, "eyeColor": 0, "mouth": 0, "showBlush": true, "outfit": {}},
		"learned": {},        # book_id -> {unit_id: true}
		"examBest": {},       # book_id|unit_id -> best correct count
		"streak": 0,
		"lastStudyDay": "",
	}


func load_game() -> void:
	var file := File.new()
	for path in [SAVE_PATH, BACKUP_PATH]:
		if file.file_exists(path) and file.open(path, File.READ) == OK:
			var parsed = JSON.parse(file.get_as_text()).result
			file.close()
			if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
				data = _merge(parsed)
				return
	emit_signal("changed")


func _merge(saved: Dictionary) -> Dictionary:
	var m := default_data()
	for key in saved:
		m[key] = saved[key]
	return m


func save_game() -> void:
	var file := File.new()
	if file.open(TEMP_PATH, File.WRITE) != OK:
		push_error("could not write profile")
		return
	file.store_string(JSON.print(data))
	file.close()
	var d := Directory.new()
	if file.file_exists(SAVE_PATH):
		d.rename(SAVE_PATH, BACKUP_PATH)
	if d.rename(TEMP_PATH, SAVE_PATH) != OK:
		if file.file_exists(BACKUP_PATH):
			d.rename(BACKUP_PATH, SAVE_PATH)
		return
	emit_signal("changed")


func grant_newbie() -> bool:
	if bool(data.get("newbieGiven", false)):
		return false
	data.newbieGiven = true
	data.points = int(data.get("points", 0)) + BONUS_NEWBIE
	save_game()
	return true


func points() -> int:
	return int(data.get("points", 0))


func add_points(n: int) -> void:
	data.points = int(data.get("points", 0)) + max(0, n)
	_touch_study_day()
	save_game()


func owns(item_id: String) -> bool:
	return bool(data.get("owned", {}).get(item_id, false))


func buy_item(item_id: String, price: int) -> bool:
	if owns(item_id) or points() < price:
		return false
	data.points = points() - price
	data.owned[item_id] = true
	save_game()
	return true


func oc_cfg() -> Dictionary:
	return data.get("oc", {})


func set_oc_slot(slot: String, value) -> void:
	var oc: Dictionary = data.get("oc", {})
	if slot in ["skin", "hair", "hairColor", "eyes", "eyeColor", "mouth"]:
		oc[slot] = int(value)
	elif slot == "showBlush":
		oc[slot] = bool(value)
	else:
		oc[slot] = value
	data.oc = oc
	save_game()


func equip(item_id: String, slot: String) -> void:
	var oc: Dictionary = data.get("oc", {})
	var outfit: Dictionary = oc.get("outfit", {})
	outfit[slot] = item_id
	oc.outfit = outfit
	data.oc = oc
	save_game()


func unequip(slot: String) -> void:
	var oc: Dictionary = data.get("oc", {})
	var outfit: Dictionary = oc.get("outfit", {})
	outfit.erase(slot)
	oc.outfit = outfit
	data.oc = oc
	save_game()


func equipped(slot: String) -> String:
	return String(data.get("oc", {}).get("outfit", {}).get(slot, ""))


# ---------------------------------------------------------- study marks --

func unit_learned(book_id: String, unit_id: String) -> bool:
	return bool(data.get("learned", {}).get(book_id, {}).get(unit_id, false))


func mark_word_learned(book_id: String, unit_id: String) -> void:
	var learned: Dictionary = data.get("learned", {})
	var per_book: Dictionary = learned.get(book_id, {})
	per_book[unit_id] = true
	learned[book_id] = per_book
	data.learned = learned
	_touch_study_day()


func all_units_learned(book: Dictionary) -> bool:
	for uid in book.get("units", []):
		if not unit_learned(String(book.get("id", "")), String(uid.get("id", ""))):
			return false
	return true


func exam_best(book_id: String, unit_id: String) -> int:
	return int(data.get("examBest", {}).get(book_id + "|" + unit_id, -1))


func record_exam(book_id: String, unit_id: String, correct: int, first_pass: bool) -> int:
	# returns bonus points granted
	var key := book_id + "|" + unit_id
	var bonus := 0
	if first_pass and correct >= EXAM_PASS:
		bonus = BONUS_EXAM_FIRST
	elif correct > exam_best(book_id, unit_id):
		bonus = (correct - exam_best(book_id, unit_id)) * BONUS_EXAM_IMPROVE
	if correct > exam_best(book_id, unit_id):
		data.examBest[key] = correct
	_touch_study_day()
	save_game()
	return bonus


func exam_passed(book_id: String, unit_id: String) -> bool:
	return exam_best(book_id, unit_id) >= EXAM_PASS


func add_card_points() -> void:
	add_points(BONUS_CARD)


func _touch_study_day() -> void:
	var today := _today()
	if String(data.get("lastStudyDay", "")) == today:
		return
	data.lastStudyDay = today
	data.streak = int(data.get("streak", 0)) + 1


func _today() -> String:
	var t := OS.get_datetime()
	return "%04d-%02d-%02d" % [t.year, t.month, t.day]


func reset_game() -> void:
	data = default_data()
	save_game()
