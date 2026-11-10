extends CanvasLayer
class_name HUD
## Минимальный HUD: прицел, подсказка действия, номер текущей комнаты
## (отладочная строка, можно убрать) и затемнение для переходов.

const CrosshairScript := preload("res://scripts/Crosshair.gd")

var prompt_label: Label
var room_label: Label
var hint_label: Label
var fade_rect: ColorRect


func _ready() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cross := Control.new()
	cross.set_script(CrosshairScript)
	root.add_child(cross)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -16
	cross.offset_top = -16
	cross.offset_right = 16
	cross.offset_bottom = 16
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE

	room_label = Label.new()
	root.add_child(room_label)
	room_label.offset_left = 16
	room_label.offset_top = 12
	room_label.offset_right = 620
	room_label.offset_bottom = 44
	room_label.add_theme_font_size_override("font_size", 16)
	room_label.modulate = Color(0.75, 0.78, 0.82, 0.9)
	room_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hint_label = Label.new()
	root.add_child(hint_label)
	hint_label.anchor_left = 1.0
	hint_label.anchor_right = 1.0
	hint_label.offset_left = -640
	hint_label.offset_top = 12
	hint_label.offset_right = -16
	hint_label.offset_bottom = 60
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.modulate = Color(0.7, 0.72, 0.75, 0.55)
	hint_label.text = "WASD — движение · мышь — обзор · E — люк · C — присесть/ползти · Shift — бег · Space — прыжок · Esc — мышь"
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	prompt_label = Label.new()
	root.add_child(prompt_label)
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_left = -400
	prompt_label.offset_top = -150
	prompt_label.offset_right = 400
	prompt_label.offset_bottom = -110
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.modulate = Color(0.9, 0.92, 0.95, 0.95)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	fade_rect = ColorRect.new()
	root.add_child(fade_rect)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.modulate = Color(1, 1, 1, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_prompt(text: String) -> void:
	if prompt_label.text != text:
		prompt_label.text = text


func set_room(text: String) -> void:
	if room_label.text != text:
		room_label.text = text


func fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.22)
	await tw.finished


func fade_in() -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.4)
	await tw.finished
