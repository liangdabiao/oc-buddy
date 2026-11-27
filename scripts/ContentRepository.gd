extends Node

# Loads oc-buddy content: books.json (13 PEP textbooks / 92 units / 3,493
# words), grammar.json (13 points), shop.json (50 wardrobe items) and
# oc_manifest.json (OC layered-sprite piece map).

var books: Array = []
var grammar: Array = []
var shop_items: Array = []
var oc_manifest: Dictionary = {}

var units_by_book: Dictionary = {}       # book id -> [unit dicts]
var words_total := 0


func _ready() -> void:
	var file := File.new()
	if file.open("res://data/books.json", File.READ) == OK:
		var parsed = JSON.parse(file.get_as_text()).result
		file.close()
		if parsed is Dictionary:
			books = parsed.get("books", [])
	for book in books:
		units_by_book[String(book.get("id", ""))] = book.get("units", [])
		for unit in book.get("units", []):
			words_total += (unit.get("words", []) as Array).size()

	if file.open("res://data/grammar.json", File.READ) == OK:
		var parsed2 = JSON.parse(file.get_as_text()).result
		file.close()
		if parsed2 is Dictionary:
			grammar = parsed2.get("points", [])

	if file.open("res://data/shop.json", File.READ) == OK:
		var parsed3 = JSON.parse(file.get_as_text()).result
		file.close()
		if parsed3 is Dictionary:
			shop_items = parsed3.get("items", [])

	if file.open("res://assets/oc/oc_manifest.json", File.READ) == OK:
		var parsed4 = JSON.parse(file.get_as_text()).result
		file.close()
		if parsed4 is Dictionary:
			oc_manifest = parsed4


func book_count() -> int:
	return books.size()


func get_book(index: int) -> Dictionary:
	if index < 0 or index >= books.size():
		return {}
	return books[index]


func book_by_id(book_id: String) -> Dictionary:
	for b in books:
		if String(b.get("id", "")) == book_id:
			return b
	return {}


func units_for_book(book_id: String) -> Array:
	return units_by_book.get(book_id, [])


func grammar_count() -> int:
	return grammar.size()


func grammar_for_book(book_id: String) -> Dictionary:
	# 13 points, one per book in upstream order; fall back to a shared card
	var idx := 0
	for i in range(books.size()):
		if String(books[i].get("id", "")) == book_id:
			idx = i
			break
	if idx < grammar.size():
		return grammar[idx]
	return grammar[0] if not grammar.empty() else {}


func shop_items_for_slot(slot: String) -> Array:
	var out: Array = []
	for item in shop_items:
		if String(item.get("slot", "")) == slot:
			out.append(item)
	return out


func shop_item(item_id: String) -> Dictionary:
	for item in shop_items:
		if String(item.get("id", "")) == item_id:
			return item
	return {}


# piece lookup for the OC renderer: (slot, key) -> png file
func oc_png(slot: String, key: String) -> String:
	for piece in oc_manifest.get("pieces", []):
		if String(piece.get("slot", "")) == slot and String(piece.get("key", "")) == key:
			return "res://assets/oc/" + String(piece.get("png", "")).replace(".png", ".pngraw")
	return ""
