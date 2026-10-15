class_name SegmentBar
extends Control
## 技能面板的一段（02 §7.3）：一级一段，显示 已投入 / 阈值；阶段门外的段灰显。

var fill: float = 0.0       # 0..1
var locked: bool = false
var lit: bool = false


func setup(f: float, is_lit: bool, is_locked: bool, tip: String) -> SegmentBar:
	fill = f
	lit = is_lit
	locked = is_locked
	tooltip_text = tip
	custom_minimum_size = Vector2(46, 18)
	return self


func _draw() -> void:
	var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	draw_rect(r, Color("#14151d"))
	if fill > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), UIKit.ACCENT if lit else Color("#8a6d2a"))
	draw_rect(r, Color(1, 1, 1, 0.12 if locked else 0.45), false, 1.0)
	if locked:
		draw_line(r.position, r.end, Color(1, 1, 1, 0.12), 1.0)
