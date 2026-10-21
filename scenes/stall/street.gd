extends Control
## 街区选址（01 §6.9）：沿街走，看哪里人多；不能在别的商贩排他半径内摆摊。
## 人流密度不直接显示，只能从走过的行人多少来判断。选址时时间不走。

const WALK_SPEED := 8.0
## 横穿街慢一些：街只有几格宽
const CROSS_SPEED := 4.0

var s: GameState
var player_x := 2.0
var player_y := 3.2
## 玩家最后一次走的方向（格坐标），决定朝向；停下来也保持
var player_dir := Vector2(1, 0)
var walkers: Array = []   # [{x, y, vx, life}]
var _msg: Label
var _msg_time := 0.0


func _ready() -> void:
	s = Game.state
	var top := UIKit.vbox(4)
	top.position = Vector2(16, 12)
	add_child(top)
	top.add_child(UIKit.label("%s　找个地方摆摊" % s.clock.label(), 20, UIKit.ACCENT))
	top.add_child(UIKit.label("方向键或 WASD 走：← → 沿街，↑ ↓ 横穿街。空格或下面的按钮在脚下摆摊。人多的地方生意好，但商贩也扎堆；离别的摊子中心太近（虚线圈内）不能摆。", 14, UIKit.MUTED))
	var bar := UIKit.hbox(10)
	bar.position = Vector2(16, 650)
	add_child(bar)
	bar.add_child(UIKit.button("在这里摆摊", _try_place, 18))
	bar.add_child(UIKit.button("回去重新规划", func(): Game.goto("planning")))
	_msg = UIKit.label("", 18, UIKit.BAD)
	_msg.position = Vector2(16, 600)
	add_child(_msg)
	# 预热行人
	for i in 200:
		_step_walkers(0.1)


func _process(dt: float) -> void:
	var dir := _move_dir()
	if dir != Vector2.ZERO:
		player_dir = dir
	player_x = clampf(player_x + dir.x * WALK_SPEED * dt, 0.5, s.street.length - 0.5)
	player_y = clampf(player_y + dir.y * CROSS_SPEED * dt, MIN_Y, MAX_Y)
	_step_walkers(dt)
	if _msg_time > 0.0:
		_msg_time -= dt
		if _msg_time <= 0.0:
			_msg.text = ""
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_SPACE or e.keycode == KEY_ENTER):
		_try_place()


## 行人按人流场的密度在各处出现、走一小段后消失；只是视觉，不影响结算。
func _step_walkers(dt: float) -> void:
	var cell := 0.0
	while cell < s.street.length:
		if randf() < s.street.density(cell + 0.5, 0.35) * 0.5 * dt:
			walkers.append({"x": cell + randf(), "y": randf_range(-50, 50), "vx": randf_range(1.0, 1.8) * (1 if randf() < 0.5 else -1), "life": randf_range(2.0, 4.0), "seed": randi() % 1000})
		cell += 1.0
	for w in walkers:
		w["x"] += w["vx"] * dt
		w["life"] -= dt
	walkers = walkers.filter(func(w): return w["life"] > 0.0)


## 四向移动（不走斜线）：← → / A D 沿街（gx），↑ ↓ / W S 横穿街（gy，↑ 往店面那侧）。同时按时沿街优先。
func _move_dir() -> Vector2:
	var h := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		h = -1.0
	elif Input.is_key_pressed(KEY_D):
		h = 1.0
	if h != 0.0:
		return Vector2(signf(h), 0)
	var v := Input.get_axis("ui_up", "ui_down")
	if Input.is_key_pressed(KEY_W):
		v = -1.0
	elif Input.is_key_pressed(KEY_S):
		v = 1.0
	return Vector2(0, signf(v))


## 镜头跟着玩家沿街走：参考点（玩家 x、街中间那排）固定在屏幕这个位置；横穿街时镜头不动。
const CAMERA_AT := Vector2(640, 420)
## 镜头参考的那一排（格坐标 gy）；0 和 5 是人行道，1–4 是街面，0 以里是店面
const CAMERA_GY := 3.2
## 玩家能走的横穿街范围：两侧人行道之间
const MIN_Y := 0.3
const MAX_Y := 5.7
const VIEW_M := 18


func _origin() -> Vector2:
	return Iso.snap(CAMERA_AT - Iso.to_screen(Vector2(player_x, CAMERA_GY), Vector2.ZERO))


func _walker_g(w: Dictionary) -> Vector2:
	return Vector2(float(w["x"]), 1.3 + (float(w["y"]) + 50.0) / 100.0 * 3.4)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#14151d"))
	var o := _origin()
	var x0 := maxi(0, floori(player_x) - VIEW_M)
	var x1 := mini(ceili(s.street.length), floori(player_x) + VIEW_M)
	# 地面：店面后的空地、人行道、街面、对面的花坛
	for x in range(x0, x1):
		for gy in range(-4, 9):
			var kind := "lot"
			var kerb := ""
			if gy == 0 or gy == 5:
				kind = "pavement"
				kerb = "se" if gy == 0 else "nw"
			elif gy > 0 and gy < 5:
				kind = "road"
			elif gy > 5:
				kind = "grass"
			Iso.draw_ground(self, o, Vector2(x, gy), kind, x * 7 + gy * 13, kerb)
	# 别的摊子的排他范围：以摊子中心为圆心的圆，站进去就不能摆
	for v in s.street.vendors:
		var c := Street.vendor_pos(v)
		if absf(c.x - player_x) < VIEW_M:
			var inside := Vector2(player_x, player_y).distance_to(c) < float(v["radius"])
			_draw_ground_circle(o, c, float(v["radius"]), Color(UIKit.BAD, 0.85 if inside else 0.35), inside)
	# 站位提示：脚下这格能不能摆
	var ok := s.street.can_place(player_x, player_y)
	Iso.draw_tile(self, o, Vector2(player_x - 0.5, player_y - 0.5), Color(UIKit.GOOD if ok else UIKit.BAD, 0.45), 1.0, 1.0, UIKit.GOOD if ok else UIKit.BAD)
	# 店面一排（最靠里，先画）
	var bx := x0 - (x0 % 4)
	while bx < x1:
		_draw_building(o, bx)
		bx += 4
	# 摊子、行人、玩家按远近排序再画
	var things: Array = []
	for v in s.street.vendors:
		var c := Street.vendor_pos(v)
		if absf(c.x - player_x) < VIEW_M:
			things.append({"g": c - Vector2(0, 0.3), "kind": "vendor"})
	for w in walkers:
		if float(w["x"]) >= 0.0 and float(w["x"]) <= s.street.length:
			things.append({"g": _walker_g(w), "kind": "walker", "w": w})
	things.append({"g": Vector2(player_x, player_y), "kind": "player"})
	things.sort_custom(func(a, b): return Iso.depth(a["g"]) < Iso.depth(b["g"]))
	var font := get_theme_default_font()
	var t := Time.get_ticks_msec() / 1000.0
	for th in things:
		var g: Vector2 = th["g"]
		match th["kind"]:
			"vendor":
				_draw_vendor_stall(o, g)
			"walker":
				var w: Dictionary = th["w"]
				var fit := Iso.outfit_full(int(w["seed"]))
				var p := Iso.to_screen(g, o)
				var a := clampf(float(w["life"]), 0.0, 1.0)
				_draw_walker(p, fit, float(w["vx"]), t + float(w["seed"]) * 0.1, a)
			"player":
				var p := Iso.to_screen(g, o)
				var f := Iso.facing_of(player_dir)
				Iso.draw_person(self, p, UIKit.ACCENT, Color("#2a2026"), f[0], t if _walking() else 0.0, f[1], 1.0, Iso.Hair.SHORT, Color("#3a3a4a"))
				draw_string(font, p + Vector2(-30, -70), "你", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, UIKit.TEXT)


func _walking() -> bool:
	return _move_dir() != Vector2.ZERO


## 地面上的圆（斜 45° 下看是个扁椭圆）：虚线描边，inside 时淡淡填一层。
func _draw_ground_circle(o: Vector2, c: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		pts.append(Iso.to_screen(c + Vector2(cos(a), sin(a)) * r, o))
	if filled:
		draw_colored_polygon(pts, Color(col, 0.18))
	for i in range(0, 48, 2):
		draw_line(pts[i], pts[i + 1], col, 2.0)


## 路人：沿街走（gx 方向是屏幕右下，往回走是左上，背对镜头）。快消失时变淡。
func _draw_walker(p: Vector2, fit: Dictionary, vx: float, phase: float, a: float) -> void:
	var body: Color = fit["top"]
	var pants: Color = fit["pants"]
	body.a = a
	pants.a = a
	var f := Iso.facing_of(Vector2(vx, 0))
	Iso.draw_person(self, p, body, fit["hair"], f[0], phase, f[1], 1.0, fit["style"], pants, fit["scarf"])


func _draw_building(o: Vector2, bx: int) -> void:
	var hsh := absi(hash(bx * 7919 + int(s.street.length)))
	const WALLS := ["#b7a58a", "#a4826a", "#8a9aa8", "#c2b59b", "#9a8a7a", "#a89880"]
	const ROOFS := ["#7a3a32", "#3a4a6a", "#5a5a5a", "#6a4a2a"]
	var wall := Color(WALLS[hsh % WALLS.size()])
	var h := 70.0 + float(hsh % 4) * 14.0
	var g := Vector2(bx + 0.1, -2.2)
	Iso.draw_box(self, o, g, 3.8, 2.0, h, wall, Color(ROOFS[(hsh / 5) % ROOFS.size()]))
	# 朝街那面：门、窗、招牌
	Iso.draw_face_rect(self, o, g, 3.8, 2.0, 0.12, 0.3, 0.0, 30.0, Color("#4a3a2a"))
	Iso.draw_face_rect(self, o, g, 3.8, 2.0, 0.42, 0.62, 10.0, 28.0, Color("#bcd4e0"))
	Iso.draw_face_rect(self, o, g, 3.8, 2.0, 0.72, 0.9, 10.0, 28.0, Color("#bcd4e0"))
	Iso.draw_face_rect(self, o, g, 3.8, 2.0, 0.1, 0.9, h - 22.0, h - 10.0, Color(ROOFS[(hsh / 3) % ROOFS.size()]).lightened(0.2))
	if h > 90.0:
		Iso.draw_face_rect(self, o, g, 3.8, 2.0, 0.42, 0.62, 44.0, 62.0, Color("#bcd4e0"))
		Iso.draw_face_rect(self, o, g, 3.8, 2.0, 0.72, 0.9, 44.0, 62.0, Color("#bcd4e0"))


## 别的商贩：摊主站在桌后（店面那侧）面朝街，桌上有块布，头顶撑着棚子。
func _draw_vendor_stall(o: Vector2, g: Vector2) -> void:
	var f := Iso.facing_of(Vector2(0, 1))
	var fit := Iso.outfit_full(int(g.x * 31.0))
	Iso.draw_person(self, Iso.to_screen(g + Vector2(0, -0.5), o), fit["top"], fit["hair"], f[0], 0.0, f[1], 1.0, fit["style"], fit["pants"])
	var tg := g + Vector2(-0.7, 0.0)
	Iso.draw_stall_table(self, o, tg, 1.4, 0.6, 16.0, Color("#7a4b3a"), Color("#4a6a8a"))
	var canopy := o + Vector2(0, -60)
	for c in [tg, tg + Vector2(1.4, 0), tg + Vector2(1.4, 0.6), tg + Vector2(0, 0.6)]:
		var p := Iso.snap(Iso.to_screen(c, o))
		draw_rect(Rect2(p + Vector2(-Iso.PX * 0.5, -60), Vector2(Iso.PX, 60)), Color("#3a2a20"))
	Iso.draw_box(self, canopy, tg + Vector2(-0.15, -0.15), 1.7, 0.9, 6.0, Color("#c85a3c"), Color("#e07a5a"))
	draw_string(get_theme_default_font(), Iso.to_screen(g, o) + Vector2(-20, -84), "商贩", HORIZONTAL_ALIGNMENT_CENTER, 40, 13, UIKit.MUTED)


func _try_place() -> void:
	if not s.street.can_place(player_x, player_y):
		_msg.text = "这里离别的摊子太近了，人家不让摆。"
		_msg_time = 2.5
		return
	Game.stall_x = player_x
	Game.goto("stall")
