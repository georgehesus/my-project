extends Control
## Прицел: точка + четыре риски.

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, 2.0, Color(0.12, 0.12, 0.13, 0.9))
	var gap := 6.0
	var len := 5.0
	var col := Color(0.12, 0.12, 0.13, 0.75)
	draw_line(c + Vector2(0, -gap), c + Vector2(0, -gap - len), col, 1.6)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, 1.6)
	draw_line(c + Vector2(-gap, 0), c + Vector2(-gap - len, 0), col, 1.6)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, 1.6)
