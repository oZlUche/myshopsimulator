class_name AreaView
extends Control
## 摆摊周遭 N×M 区域（01 §6.9），开罗式斜 45° 视角：范围外一片黑，什么信息都没有。
## 行人沿街（远处两排）横穿；被吸引的走到摊前，成为客人。纯视觉，结算在 StallSession。
## 格坐标：gx 沿街，gy 0–1 是街面，2 是客人站的地方，3 是摊桌，4 是你。

const ROWS := 5
const TABLE_GY := 2.9
const VISITOR_GY := 2.35
const PLAYER_GY := 4.0

## 点到了某位客人（问价的去讲价、等货的交货，由摊位界面决定）
signal visitor_clicked(visitor: Dictionary)

var session: StallSession
var walkers: Array = []   # [{g, vel, life, stayed, seed}]
## 客人编号 → 显示用
var visitor_numbers: Dictionary = {}


func cols() -> int:
	return session.area_radius() * 2 + 1


func center_gx() -> float:
	return cols() * 0.5


## 整个菱形区域连同人物高度要塞进控件里：返回 {origin, k}（未缩放的原点、缩放）。
func _fit() -> Dictionary:
	var n := float(cols() + ROWS)
	var w := n * Iso.TW * 0.5
	var h := n * Iso.TH * 0.5 + 60.0
	# 像素风：缩放只取 0.5 的整数倍，原点对齐像素网格，精灵才不会糊
	var k := maxf(0.5, floorf(minf(1.5, minf(size.x / w, size.y / h)) * 2.0) / 2.0)
	# 菱形最左角是 (0, ROWS)，最上角是 (0, 0)
	var left := Iso.to_screen(Vector2(0, ROWS), Vector2.ZERO).x
	var origin := Iso.snap(Vector2((size.x / k - w) * 0.5 - left, (size.y / k - h) * 0.5 + 50.0))
	return {"origin": origin, "k": k}


func add_walker(stayed: bool) -> void:
	var from_left := randf() < 0.5
	var gy := randf_range(0.2, 1.8)
	walkers.append({
		"g": Vector2(-0.8 if from_left else cols() + 0.8, gy),
		"vel": Vector2((1 if from_left else -1) * randf_range(1.2, 2.0), 0),
		"life": 20.0, "stayed": stayed, "seed": randi() % 1000,
	})


func step(dt: float) -> void:
	var stall := Vector2(center_gx(), VISITOR_GY)
	for w in walkers:
		if w["stayed"]:
			var to: Vector2 = stall - w["g"]
			if to.length() < 0.25:
				w["life"] = 0.0
			else:
				w["vel"] = to.normalized() * 2.0
				w["g"] += w["vel"] * dt
		else:
			w["g"] += w["vel"] * dt
			if w["g"].x < -1.0 or w["g"].x > cols() + 1.0:
				w["life"] = 0.0
	walkers = walkers.filter(func(w): return w["life"] > 0.0)
	queue_redraw()


func visitor_g(i: int) -> Vector2:
	# 沿摊前排开，人多了前后错开两排，免得叠在一起
	var n := maxi(1, session.visitors.size())
	var span := minf(cols() - 0.6, 1.1 * n)
	return Vector2(center_gx() - span * 0.5 + span * (i + 0.5) / n, VISITOR_GY - 0.6 * (i % 2))


## 客人身体在控件坐标里的点击范围。
func visitor_rect(i: int) -> Rect2:
	var f := _fit()
	var k: float = f["k"]
	var foot := Iso.to_screen(visitor_g(i), f["origin"])
	var r := Iso.person_rect(foot)
	return Rect2(r.position * k, r.size * k)


func _gui_input(e: InputEvent) -> void:
	if session == null or not (e is InputEventMouseButton) or not e.pressed or e.button_index != MOUSE_BUTTON_LEFT:
		return
	# 前排的客人挡住后排的，从近到远找
	var order := range(session.visitors.size())
	order.sort_custom(func(a, b): return Iso.depth(visitor_g(a)) > Iso.depth(visitor_g(b)))
	for i in order:
		if visitor_rect(i).has_point(e.position):
			visitor_clicked.emit(session.visitors[i])
			accept_event()
			return


func _draw() -> void:
	if session == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var f := _fit()
	var o: Vector2 = f["origin"]
	var k: float = f["k"]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	for gx in cols():
		for gy in ROWS:
			# 远处两排是街面，人行道挨着街的那条边有路缘石
			Iso.draw_ground(self, o, Vector2(gx, gy), "road" if gy < 2 else "pavement", gx * 7 + gy * 13, "nw" if gy == 2 else "")
	# 远近排序：行人、客人、摊桌、你
	var things: Array = []
	for w in walkers:
		things.append({"g": w["g"], "kind": "walker", "w": w})
	for i in session.visitors.size():
		things.append({"g": visitor_g(i), "kind": "visitor", "v": session.visitors[i]})
	things.append({"g": Vector2(center_gx(), TABLE_GY + 0.7), "kind": "table"})
	things.append({"g": Vector2(center_gx(), PLAYER_GY), "kind": "player"})
	things.sort_custom(func(a, b): return Iso.depth(a["g"]) < Iso.depth(b["g"]))
	var font := get_theme_default_font()
	var t := Time.get_ticks_msec() / 1000.0
	for th in things:
		var p := Iso.to_screen(th["g"], o)
		match th["kind"]:
			"walker":
				var w: Dictionary = th["w"]
				var fit := Iso.outfit_full(int(w["seed"]))
				var vel: Vector2 = w["vel"]
				# 往 gx 负方向或往里（gy 变小）走就是背对镜头
				var fc := Iso.facing_of(vel)
				Iso.draw_person(self, p, fit["top"], fit["hair"], fc[0], t + float(w["seed"]) * 0.1, fc[1], 1.0, fit["style"], fit["pants"], fit["scarf"])
			"visitor":
				var v: Dictionary = th["v"]
				var fit := Iso.outfit_full(hash(v["customer"].id))
				# 客人站在摊前，面朝摊桌（+gy）
				var fc := Iso.facing_of(Vector2(0, 1))
				Iso.draw_person(self, p, fit["top"], fit["hair"], fc[0], 0.0, fc[1], 1.0, fit["style"], fit["pants"], fit["scarf"])
				var col := {"browsing": Color("#b8b5c4"), "asking": UIKit.ACCENT, "haggling": Color("#6fa8dc"), "waiting_item": UIKit.GOOD}.get(v["state"], Color.GRAY) as Color
				draw_string(font, p + Vector2(-14, -62), "#%d" % visitor_numbers.get(v["customer"].id, 0), HORIZONTAL_ALIGNMENT_CENTER, 28, 13, col)
				var bubble_at := p + Vector2(14, -76)
				if v["state"] == "asking":
					Iso.draw_bubble(self, bubble_at, "ask")
				elif v["state"] == "haggling":
					Iso.draw_bubble(self, bubble_at, "haggle")
				elif v["state"] == "waiting_item":
					# 伸着手等货：气泡里一条小围巾，脚下一截等待条
					Iso.draw_bubble(self, bubble_at, "wait")
					var left := clampf(float(v["wait"]) / maxf(session.wait_for_item(v["customer"]), 1.0), 0.0, 1.0)
					draw_rect(Rect2(p + Vector2(-12, 4), Vector2(24, 3)), Color(0, 0, 0, 0.5))
					draw_rect(Rect2(p + Vector2(-12, 4), Vector2(24 * left, 3)), UIKit.GOOD if left > 0.3 else Color("#e05a4f"))
			"table":
				_draw_table(o)
			"player":
				# 你站在摊桌后面，面朝街（-gy），背对镜头
				var fc := Iso.facing_of(Vector2(0, -1))
				Iso.draw_person(self, p, UIKit.ACCENT, Color("#2a2026"), fc[0], 0.0, fc[1], 1.0, Iso.Hair.SHORT, Color("#3a3a4a"))
				draw_string(font, p + Vector2(-30, 16), "你", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, UIKit.TEXT)
	# 范围边框
	var edge := Iso.tile_points(Vector2.ZERO, o, cols(), ROWS)
	edge.append(edge[0])
	draw_polyline(edge, Color(1, 1, 1, 0.25), Iso.PX)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_string(font, Vector2(8, 18), "周遭 %d×%d 格（吆喝越好看得越远）" % [cols(), ROWS], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)


## 摊桌：铺着桌布的板子，上面按摊位一格一格摞着叠好的围巾（从侧面能看到每份的颜色）。
func _draw_table(o: Vector2) -> void:
	var tables := session.s.inventory.slots_of_type("StallTable")
	var n := maxi(1, tables.size())
	var w := maxf(2.4, n * 0.9)
	var g := Vector2(center_gx() - w * 0.5, TABLE_GY)
	const H := 14.0
	Iso.draw_stall_table(self, o, g, w, 0.7, H)
	for j in tables.size():
		var st: ItemStack = tables[j].stack
		var cell := g + Vector2(w * (j + 0.5) / n, 0.38)
		var base := Iso.to_screen(cell, o) + Vector2(0, -H)
		for i in st.height():
			Iso.draw_scarf_fold(self, base - Vector2(0, st.layer_of(i) * Iso.FOLD_STEP), UIKit.sku_color(st.items[i].sku_id), i * 7 + j)
