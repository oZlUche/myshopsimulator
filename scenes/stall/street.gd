extends Control
## 街区选址（01 §6.9）：沿街走，看哪里人多；不能在别的商贩排他半径内摆摊。
## 人流密度不直接显示，只能从走过的行人多少来判断。选址时时间不走。

const WALK_SPEED := 8.0

var s: GameState
var player_x := 2.0
var walkers: Array = []   # [{x, y, vx, life}]
var _msg: Label
var _msg_time := 0.0


func _ready() -> void:
	s = Game.state
	var top := UIKit.vbox(4)
	top.position = Vector2(16, 12)
	add_child(top)
	top.add_child(UIKit.label("%s　找个地方摆摊" % s.clock.label(), 20, UIKit.ACCENT))
	top.add_child(UIKit.label("← → 或 A D 沿街走；空格或下面的按钮在脚下摆摊。人多的地方生意好，但商贩也扎堆；离商贩太近不能摆。", 14, UIKit.MUTED))
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
	var dir := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		dir = -1.0
	elif Input.is_key_pressed(KEY_D):
		dir = 1.0
	player_x = clampf(player_x + dir * WALK_SPEED * dt, 0.5, s.street.length - 0.5)
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


## 镜头跟着玩家走：玩家脚下固定在屏幕这个位置。
const CAMERA_AT := Vector2(640, 420)
## 玩家沿街走的那一排（格坐标 gy）；1–5 是街面，0 以里是店面
const PLAYER_GY := 3.2
const VIEW_M := 18


func _origin() -> Vector2:
	return CAMERA_AT - Iso.to_screen(Vector2(player_x, PLAYER_GY), Vector2.ZERO)


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
			var col: Color
			if gy < 0:
				col = Color("#3a3d33")
			elif gy == 0 or gy == 5:
				col = Color("#8c8578") if (x + gy) % 2 == 0 else Color("#837c70")
			elif gy < 5:
				col = Color("#5d5a66") if (x + gy) % 2 == 0 else Color("#56535f")
			else:
				col = Color("#3f5a3a") if (x * 3 + gy) % 5 != 0 else Color("#4a6a42")
			Iso.draw_tile(self, o, Vector2(x, gy), col)
	# 站位提示：脚下这格能不能摆
	var ok := s.street.can_place(player_x)
	Iso.draw_tile(self, o, Vector2(player_x - 0.5, PLAYER_GY - 0.5), Color(UIKit.GOOD if ok else UIKit.BAD, 0.45), 1.0, 1.0, UIKit.GOOD if ok else UIKit.BAD)
	# 店面一排（最靠里，先画）
	var bx := x0 - (x0 % 4)
	while bx < x1:
		_draw_building(o, bx)
		bx += 4
	# 摊子、行人、玩家按远近排序再画
	var things: Array = []
	for v in s.street.vendors:
		var vx := float(v["x"])
		if absf(vx - player_x) < VIEW_M:
			things.append({"g": Vector2(vx, 1.2), "kind": "vendor"})
	for w in walkers:
		if float(w["x"]) >= 0.0 and float(w["x"]) <= s.street.length:
			things.append({"g": _walker_g(w), "kind": "walker", "w": w})
	things.append({"g": Vector2(player_x, PLAYER_GY), "kind": "player"})
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
				var fit := Iso.outfit(int(w["seed"]))
				var p := Iso.to_screen(g, o)
				var a := clampf(float(w["life"]), 0.0, 1.0)
				_draw_walker(p, fit, float(w["vx"]), t + float(w["seed"]) * 0.1, a)
			"player":
				var p := Iso.to_screen(g, o)
				Iso.draw_person(self, p, UIKit.ACCENT, Color("#2a2026"), 1.0, t if _walking() else 0.0, false, 1.2)
				draw_string(font, p + Vector2(-30, -48), "你", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, UIKit.TEXT)


func _walking() -> bool:
	return Input.get_axis("ui_left", "ui_right") != 0.0 or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)


## 路人：沿街走（gx 方向是屏幕右下，往回走是左上，背对镜头）。快消失时变淡。
func _draw_walker(p: Vector2, fit: Array, vx: float, phase: float, a: float) -> void:
	var body: Color = fit[0]
	var hair: Color = fit[1]
	body.a = a
	hair.a = a
	Iso.draw_person(self, p, body, hair, 1.0 if vx > 0.0 else -1.0, phase, vx < 0.0)


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


## 别的商贩：摊主站在桌后，桌上有块布，头顶撑着棚子。
func _draw_vendor_stall(o: Vector2, g: Vector2) -> void:
	Iso.draw_person(self, Iso.to_screen(g + Vector2(0, -0.5), o), Color("#6a6a7a"), Color("#1a1a1a"), 1.0)
	var tg := g + Vector2(-0.7, 0.0)
	Iso.draw_box(self, o, tg, 1.4, 0.6, 16.0, Color("#7a4b3a"), Color("#c8b089"))
	var canopy := o + Vector2(0, -44)
	for c in [tg, tg + Vector2(1.4, 0), tg + Vector2(1.4, 0.6), tg + Vector2(0, 0.6)]:
		var p := Iso.to_screen(c, o)
		draw_line(p, p + Vector2(0, -44), Color("#3a2a20"), 2.0)
	Iso.draw_box(self, canopy, tg + Vector2(-0.15, -0.15), 1.7, 0.9, 5.0, Color("#c85a3c"), Color("#e07a5a"))
	draw_string(get_theme_default_font(), Iso.to_screen(g, o) + Vector2(-20, -76), "商贩", HORIZONTAL_ALIGNMENT_CENTER, 40, 13, UIKit.MUTED)


func _try_place() -> void:
	if not s.street.can_place(player_x):
		_msg.text = "这里离别的摊子太近了，人家不让摆。"
		_msg_time = 2.5
		return
	Game.stall_x = player_x
	Game.goto("stall")
