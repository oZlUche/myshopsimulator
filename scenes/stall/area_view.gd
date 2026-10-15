class_name AreaView
extends Control
## 摆摊周遭 N×M 区域（01 §6.9）：范围外一片黑，什么信息都没有。
## 行人沿街横穿；被吸引的停到摊前，成为客人。纯视觉，结算在 StallSession。

const CELL := 40.0
const ROWS := 5

var session: StallSession
var walkers: Array = []   # [{pos, vel, life, color}]
## 客人编号 → 显示用
var visitor_numbers: Dictionary = {}


func cols() -> int:
	return session.area_radius() * 2 + 1


func grid_rect() -> Rect2:
	var w := cols() * CELL
	var h := ROWS * CELL
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)


func add_walker(stayed: bool) -> void:
	var g := grid_rect()
	var from_left := randf() < 0.5
	var y := g.position.y + CELL * randf_range(0.3, 1.7)
	var x := g.position.x - 6 if from_left else g.end.x + 6
	walkers.append({"pos": Vector2(x, y), "vel": Vector2((1 if from_left else -1) * randf_range(40, 70), 0), "life": 20.0, "stayed": stayed})


func step(dt: float) -> void:
	var g := grid_rect()
	var stall := Vector2(g.get_center().x, g.position.y + CELL * 3.0)
	for w in walkers:
		if w["stayed"]:
			var to: Vector2 = stall - w["pos"]
			if to.length() < 8.0:
				w["life"] = 0.0
			else:
				w["pos"] += to.normalized() * 70.0 * dt
		else:
			w["pos"] += w["vel"] * dt
			if w["pos"].x < g.position.x - 20 or w["pos"].x > g.end.x + 20:
				w["life"] = 0.0
	walkers = walkers.filter(func(w): return w["life"] > 0.0)
	queue_redraw()


func visitor_slot_pos(i: int) -> Vector2:
	var g := grid_rect()
	var n := maxi(1, session.visitors.size())
	var span := minf(g.size.x - CELL, CELL * n)
	return Vector2(g.get_center().x - span * 0.5 + span * (i + 0.5) / n, g.position.y + CELL * 2.5)


func _draw() -> void:
	if session == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var g := grid_rect()
	draw_rect(Rect2(g.position, Vector2(g.size.x, CELL * 2)), Color("#3b3a45"))
	draw_rect(Rect2(g.position + Vector2(0, CELL * 2), Vector2(g.size.x, CELL * 3)), Color("#4a4855"))
	for c in cols() + 1:
		draw_line(g.position + Vector2(c * CELL, 0), g.position + Vector2(c * CELL, g.size.y), Color(1, 1, 1, 0.04))
	for r in ROWS + 1:
		draw_line(g.position + Vector2(0, r * CELL), g.position + Vector2(g.size.x, r * CELL), Color(1, 1, 1, 0.04))
	# 摊子
	var cx := g.get_center().x
	draw_rect(Rect2(cx - CELL * 1.2, g.position.y + CELL * 3.1, CELL * 2.4, CELL * 0.7), Color("#8a6a4a"))
	draw_rect(Rect2(cx - 7, g.position.y + CELL * 4.0, 14, 22), UIKit.ACCENT)
	draw_string(get_theme_default_font(), Vector2(cx - 30, g.end.y - 2), "你", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, UIKit.TEXT)
	for w in walkers:
		draw_rect(Rect2(w["pos"] - Vector2(3, 6), Vector2(6, 12)), Color(0.85, 0.82, 0.75))
	var font := get_theme_default_font()
	for i in session.visitors.size():
		var v: Dictionary = session.visitors[i]
		var p := visitor_slot_pos(i)
		var col := {"browsing": Color("#b8b5c4"), "asking": UIKit.ACCENT, "haggling": Color("#6fa8dc")}.get(v["state"], Color.GRAY) as Color
		draw_rect(Rect2(p - Vector2(6, 10), Vector2(12, 20)), col)
		draw_string(font, p + Vector2(-12, -16), "#%d" % visitor_numbers.get(v["customer"].id, 0), HORIZONTAL_ALIGNMENT_CENTER, 24, 12, col)
		if v["state"] == "asking":
			draw_string(font, p + Vector2(8, -4), "？", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIKit.ACCENT)
	draw_rect(g, Color(1, 1, 1, 0.25), false, 1.0)
	draw_string(font, Vector2(8, 18), "周遭 %d×%d 格（吆喝越好看得越远）" % [cols(), ROWS], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)
