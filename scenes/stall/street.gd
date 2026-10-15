extends Control
## 街区选址（01 §6.9）：沿街走，看哪里人多；不能在别的商贩排他半径内摆摊。
## 人流密度不直接显示，只能从走过的行人多少来判断。选址时时间不走。

const PX_PER_M := 20.0
const WALK_SPEED := 8.0
const STREET_Y := 360.0

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
			walkers.append({"x": cell + randf(), "y": randf_range(-50, 50), "vx": randf_range(1.0, 1.8) * (1 if randf() < 0.5 else -1), "life": randf_range(2.0, 4.0)})
		cell += 1.0
	for w in walkers:
		w["x"] += w["vx"] * dt
		w["life"] -= dt
	walkers = walkers.filter(func(w): return w["life"] > 0.0)


func _sx(x: float) -> float:
	return 40.0 + x * PX_PER_M


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIKit.BG)
	var road := Rect2(_sx(0), STREET_Y - 80, s.street.length * PX_PER_M, 160)
	draw_rect(road, Color("#3b3a45"))
	draw_rect(Rect2(road.position.x, road.position.y - 8, road.size.x, 8), Color("#5b5866"))
	draw_rect(Rect2(road.position.x, road.end.y, road.size.x, 8), Color("#5b5866"))
	for v in s.street.vendors:
		var vx := _sx(float(v["x"]))
		draw_rect(Rect2(vx - 22, STREET_Y - 120, 44, 30), Color("#7a4b3a"))
		draw_rect(Rect2(vx - 26, STREET_Y - 132, 52, 12), Color("#c85a3c"))
		draw_string(get_theme_default_font(), Vector2(vx - 20, STREET_Y - 138), "商贩", HORIZONTAL_ALIGNMENT_CENTER, 40, 13, UIKit.MUTED)
	for w in walkers:
		if float(w["x"]) < 0.0 or float(w["x"]) > s.street.length:
			continue
		var a := clampf(float(w["life"]), 0.0, 1.0)
		draw_rect(Rect2(_sx(w["x"]) - 3, STREET_Y + float(w["y"]) - 6, 6, 12), Color(0.85, 0.82, 0.75, a))
	var px := _sx(player_x)
	var ok := s.street.can_place(player_x)
	draw_rect(Rect2(px - 7, STREET_Y + 60, 14, 24), UIKit.ACCENT)
	draw_rect(Rect2(px - 5, STREET_Y + 48, 10, 10), Color("#f0d2b0"))
	draw_line(Vector2(px, STREET_Y + 92), Vector2(px, STREET_Y + 100), UIKit.GOOD if ok else UIKit.BAD, 3.0)
	draw_string(get_theme_default_font(), Vector2(px - 30, STREET_Y + 118), "你", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, UIKit.TEXT)


func _try_place() -> void:
	if not s.street.can_place(player_x):
		_msg.text = "这里离别的摊子太近了，人家不让摆。"
		_msg_time = 2.5
		return
	Game.stall_x = player_x
	Game.goto("stall")
