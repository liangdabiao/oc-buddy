class_name UIKit
extends Reference

# Visual factory for Algo Buddy. All screens are code-generated on a fixed
# 640x480 canvas, mirroring the english-buddy / javascript-buddy template.

const FONT_PATH := "res://assets/fonts/ui.ttf"
# DejaVu Sans Mono for code blocks and math glyphs (full face, not subsetted).
const CODE_FONT_PATH := "res://assets/fonts/code.ttf"
const BG := Color("0e1420")
const PANEL := Color("17202e")
const PANEL_LIGHT := Color("223044")
const LINE := Color("33445e")
const TEXT := Color("e8eaf2")
const MUTED := Color("8fa0b8")
const GREEN := Color("7dd3a8")
const GOLD := Color("f0c674")
const RED := Color("e88b8b")
const BLUE := Color("8ab8f0")
const CODE_BG := Color("0b111c")

var font_cache: Dictionary = {}
var code_font_cache: Dictionary = {}
var texture_cache: Dictionary = {}


func font(size: int) -> DynamicFont:
	if font_cache.has(size):
		return font_cache[size]
	var result := DynamicFont.new()
	result.font_data = load(FONT_PATH)
	result.size = size
	font_cache[size] = result
	return result


func code_font(size: int) -> DynamicFont:
	if code_font_cache.has(size):
		return code_font_cache[size]
	var result := DynamicFont.new()
	var data = load(CODE_FONT_PATH)
	result.font_data = data if data != null else load(FONT_PATH)
	result.size = size
	code_font_cache[size] = result
	return result


func font_for_style(style: String, size: int) -> DynamicFont:
	return code_font(size - 2) if style == "c" else font(size)


func color_for_style(style: String) -> Color:
	match style:
		"b": return GOLD
		"c": return BLUE
		"m": return GREEN
		_: return TEXT


func style(background: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10, border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box


func panel(parent: Node, rect: Rect2, background: Color = PANEL, border: Color = LINE, radius: int = 10) -> Panel:
	var result := Panel.new()
	result.rect_position = rect.position
	result.rect_size = rect.size
	result.add_stylebox_override("panel", style(background, border, radius))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result


func label(parent: Node, text: String, rect: Rect2, size: int = 20, color: Color = TEXT, align: int = 0, wrap: bool = false, custom_font: Font = null) -> Label:
	var result := Label.new()
	result.text = text
	result.rect_position = rect.position
	result.rect_size = rect.size
	result.add_font_override("font", custom_font if custom_font != null else font(size))
	result.add_color_override("font_color", color)
	result.align = align
	result.valign = 1
	result.autowrap = wrap
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result


func texture(parent: Node, path: String, rect: Rect2) -> TextureRect:
	var result := TextureRect.new()
	result.rect_position = rect.position
	result.rect_size = rect.size
	result.expand = true
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if path != "":
		if not texture_cache.has(path):
			texture_cache[path] = load(path)
		result.texture = texture_cache[path]
	parent.add_child(result)
	return result


func progress_bar(parent: Node, rect: Rect2, value: float, color: Color = GREEN) -> void:
	panel(parent, rect, Color("1b2736"), Color(0, 0, 0, 0), 5)
	if value > 0:
		var fill_width: float = max(4, rect.size.x * clamp(value, 0, 1))
		panel(parent, Rect2(rect.position, Vector2(fill_width, rect.size.y)), color, Color(0, 0, 0, 0), 5)
