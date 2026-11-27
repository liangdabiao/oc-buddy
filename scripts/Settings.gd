extends Node

# Persisted settings (user://settings.json). The API key can also live in a
# gitignored settings.local.json next to the project for development.

const SETTINGS_PATH := "user://kid_buddy_settings.json"
const LOCAL_PATH := "res://settings.local.json"

signal changed

var api_key := ""
var voice := "Chloe"
var style_hint := "Speak in a warm, playful voice for a young child learning English. Slightly slower pace, clear pronunciation, short sentences."


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var file := File.new()
	if file.open(SETTINGS_PATH, File.READ) == OK:
		var parsed = JSON.parse(file.get_as_text()).result
		file.close()
		if parsed is Dictionary:
			api_key = String(parsed.get("api_key", api_key))
			voice = String(parsed.get("voice", voice))
			style_hint = String(parsed.get("style_hint", style_hint))
	# dev override (gitignored)
	if file.open(LOCAL_PATH, File.READ) == OK:
		var local = JSON.parse(file.get_as_text()).result
		file.close()
		if local is Dictionary and String(local.get("api_key", "")) != "":
			api_key = String(local["api_key"])


func save_settings() -> void:
	var file := File.new()
	if file.open(SETTINGS_PATH, File.WRITE) == OK:
		file.store_string(JSON.print({
			"api_key": api_key,
			"voice": voice,
			"style_hint": style_hint,
		}))
		file.close()
	emit_signal("changed")


func has_key() -> bool:
	return api_key != ""
