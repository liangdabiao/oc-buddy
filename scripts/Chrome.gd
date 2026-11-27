extends Control

# The header bar, footer hints and toasts are drawn here instead of
# App._draw(): a Control draws itself *behind* its own children, so the
# screen content would cover them. This node sits above screen_root.

var app: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0


func _draw() -> void:
	if app != null and is_instance_valid(app) and app.has_method("draw_chrome"):
		app.draw_chrome(self)
