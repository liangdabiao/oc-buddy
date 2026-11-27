extends Node2D

# Layered OC renderer. Mirrors the upstream SVG paint order exactly:
#   back_art -> hair_back -> armL -> legL(+shoe+bottom leg) -> legR ->
#   armR(+top sleeve+held) -> core body -> shoes(custom) -> bottom(hip) ->
#   top(torso) -> eyes -> mouth -> blush -> hair_front -> earring -> glasses -> hat
# Every piece PNG shares the 200x300 viewBox, rasterized at 400x600.

const PIECE_ORDER := [
	"back_art", "hair_back",
	"armL_base", "armL_top",
	"legL_base", "legL_shoe", "legL_bottom",
	"armR_base", "armR_top", "held",
	"legR_base", "legR_shoe", "legR_bottom",
	"core_body", "shoes_custom", "bottom_hip", "bottom_torso", "bottom_custom",
	"top_torso", "top_custom",
	"eyes", "mouth", "blush", "hair_front",
	"earring", "glasses", "hat",
]

var repo
var sprites: Dictionary = {}          # slot name -> Sprite2D
var cfg := {}                         # {skin,hair,hairColor,eyes,eyeColor,mouth,showBlush,outfit:{}}
var texture_scale := 1.0              # 400x600 png drawn at 200x300 local units


func setup(repository, initial_cfg: Dictionary) -> void:
	repo = repository
	var df := File.new()
	df.open("/tmp/ocview.log", File.WRITE)
	df.store_string("setup begin
")
	df.close()
	cfg = initial_cfg.duplicate(true)
	for slot in PIECE_ORDER:
		var sprite := Sprite2D.new()
		sprite.name = slot
		sprite.centered = false
		sprite.scale = Vector2(texture_scale, texture_scale)
		add_child(sprite)
		sprites[slot] = sprite
	refresh()
	var df2 := File.new()
	df2.open("/tmp/ocview.log", File.READ_WRITE)
	df2.seek_end()
	df2.store_string("setup end
")
	df2.close()


func set_cfg(key: String, value) -> void:
	cfg[key] = value
	refresh()


func equip(slot: String, item_id: String) -> void:
	var outfit: Dictionary = cfg.get("outfit", {})
	outfit[slot] = item_id
	cfg.outfit = outfit
	refresh()


func unequip(slot: String) -> void:
	var outfit: Dictionary = cfg.get("outfit", {})
	outfit.erase(slot)
	cfg.outfit = outfit
	refresh()


func refresh() -> void:
	var skin: int = int(cfg.get("skin", 0))
	var hair: int = int(cfg.get("hair", 0))
	var hair_color: int = int(cfg.get("hairColor", 0))
	var eyes: int = int(cfg.get("eyes", 0))
	var eye_color: int = int(cfg.get("eyeColor", 0))
	var mouth: int = int(cfg.get("mouth", 0))
	var show_blush: bool = bool(cfg.get("showBlush", true))
	var outfit: Dictionary = cfg.get("outfit", {})

	set_png("hair_back", repo.oc_png("hair_back", "hair_%d_%d" % [hair, hair_color]))
	set_png("armL_base", repo.oc_png("armL", "body_s%d" % skin))
	set_png("armR_base", repo.oc_png("armR", "body_s%d" % skin))
	set_png("legL_base", repo.oc_png("legL", "body_s%d" % skin))
	set_png("legR_base", repo.oc_png("legR", "body_s%d" % skin))
	set_png("core_body", repo.oc_png("core_body", "body_s%d" % skin))
	set_png("eyes", repo.oc_png("eyes", "eyes_s%d_%d_%d" % [skin, eyes, eye_color]))
	set_png("mouth", repo.oc_png("mouth", "mouth_%d_s%d" % [mouth, skin]))
	set_png("blush", repo.oc_png("blush", "blush_s%d" % skin) if show_blush else "")
	set_png("hair_front", repo.oc_png("hair_front", "hairf_%d_%d" % [hair, hair_color]))

	for slot in ["top", "bottom", "shoes", "held", "back", "earring", "glasses", "hat"]:
		var item_id := String(outfit.get(slot, ""))
		var layer := _item_layer(slot)
		if item_id == "":
			clear_layer(layer, slot)
			continue
		apply_item(slot, layer, item_id, skin)


func _item_layer(slot: String) -> String:
	match slot:
		"top": return "sleeves+torso"       # multi-piece
		"bottom": return "legs+hip"
		"shoes": return "shoeL+shoeR"
		"held": return "held"
		"back": return "back_art"
		"earring": return "earring"
		"glasses": return "glasses"
		"hat": return "hat"
	return ""


func apply_item(slot: String, layer: String, item_id: String, skin: int) -> void:
	# gather all piece pngs for this item+skin across the layers it touches
	var wanted: Array = []
	for piece in repo.oc_manifest.get("pieces", []):
		if String(piece.get("slot", "")) != "w_" + slot:
			continue
		if String(piece.get("key", "")) != item_id + "_s" + str(skin):
			continue
		if String(piece.get("png", "")) != "":
			wanted.append(String(piece["png"]))
	for png in wanted:
		for layer_name in _layer_names(layer):
			if png.ends_with("_" + layer_name + ".png"):
				set_png(layer_name, "res://assets/oc/" + png)
		# static items (hat/earring/glasses/held/back/custom) map 1:1
		if layer in ["held", "back_art", "earring", "glasses", "hat"] or png.find("_" + layer) == -1:
			if slot in ["held", "back", "earring", "glasses", "hat"]:
				set_png(layer, "res://assets/oc/" + png)


func _layer_names(layer: String) -> Array:
	match layer:
		"sleeves+torso":
			return ["armL_top", "armR_top", "top_torso", "top_custom"]
		"legs+hip":
			return ["legL_bottom", "legR_bottom", "bottom_hip", "bottom_torso", "bottom_custom"]
		"shoeL+shoeR":
			return ["legL_shoe", "legR_shoe", "shoes_custom"]
	return [layer]


func set_png(slot: String, path: String) -> void:
	var sprite: Sprite2D = sprites.get(slot, null)
	if sprite == null:
		return
	if path == "":
		sprite.texture = null
		sprite.visible = false
		return
	var tex = load(path) if ResourceLoader.exists(path) else null
	sprite.texture = tex
	sprite.visible = tex != null
