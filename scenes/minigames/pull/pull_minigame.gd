class_name PullMinigame
extends Control
## 抽取小游戏（03 §2.1）：侧面看货堆，按住目标货的发力点拖出来。
## 最佳：按角落、斜向 30°–45°、先慢后快。上方越重，货越"跟不上手"。
## 结束时把拖动轨迹换算成 pull_input，交给 ActionAPI 走统一的倒塌结算。

signal finished(success: bool, pull_input: Dictionary, seconds: float)

const BAR_W := 360.0
const BAR_H := 24.0

var stack: ItemStack
var index: int
var title := ""

var _holding := false
var _point := "center"
var _samples: Array = []
var _offset := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _elapsed := 0.0
var _hint := ""
var _cancel: Button
var _done := false


func setup(st: ItemStack, idx: int, t: String) -> PullMinigame:
	stack = st
	index = idx
	title = t
	mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.full_rect(self)
	_hint = "按住白框那份货的一角，斜着往上拉，先慢后快。"
	return self


func _ready() -> void:
	_cancel = UIKit.button("算了，不抽了", func(): _done = true; finished.emit(false, {}, _elapsed))
	add_child(_cancel)
	resized.connect(_place_cancel)
	_place_cancel.call_deferred()


func _place_cancel() -> void:
	_cancel.position = _panel().end - _cancel.size - Vector2(16, 16)


func _panel() -> Rect2:
	return Rect2(size * 0.5 - Vector2(360, 200), Vector2(720, 400))


func _target_rect() -> Rect2:
	var r := _bar_rect(index)
	return Rect2(r.position + _offset, r.size)


func _bar_rect(i: int) -> Rect2:
	var base := Vector2(_panel().position.x + 140, _panel().end.y - 70)
	return Rect2(base.x, base.y - (i + 1) * BAR_H, BAR_W, BAR_H - 2)


func _process(dt: float) -> void:
	if _done:
		return
	_elapsed += dt
	if _holding:
		drag_step(get_local_mouse_position(), dt)
	queue_redraw()


## 手移动到 m（面板坐标）。拆出来方便测试直接喂轨迹。
func drag_step(m: Vector2, dt: float) -> void:
	if not _holding:
		return
	var hand := m - _last_mouse
	_last_mouse = m
	_samples.append({"t": _elapsed, "pos": m})
	if hand.length() > 0.0:
		var theta := rad_to_deg(atan2(absf(hand.y), absf(hand.x)))
		var v_hand := hand.length() / maxf(dt, 0.001)
		var v_item := PullPhysics.item_speed(v_hand, stack.weight_above(index), theta, _point)
		# 货只能往外（左右）和往上被带出，往下压不动
		var step := hand.normalized() * v_item * dt
		step.y = minf(step.y, 0.0)
		_offset += step
		_offset.y = maxf(_offset.y, -BAR_H * 1.5)
	queue_redraw()
	if absf(_offset.x) >= BAR_W * 0.85:
		_holding = false
		_done = true
		finished.emit(true, PullPhysics.input_from_drag(_samples, _point), _elapsed)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _target_rect().has_point(e.position):
			_holding = true
			_point = _point_kind(e.position)
			_samples = [{"t": _elapsed, "pos": e.position}]
			_last_mouse = e.position
			_hint = {"corner": "抓住了角。", "edge": "抓在边上，不太好使力。", "center": "抓在中间，很难带出来。"}[_point]
		elif not e.pressed and _holding:
			# 没拉出来就松手：货滑回去，可以再来
			_holding = false
			_offset = Vector2.ZERO
			_hint = "没拉出来，货又缩回去了。再试一次。"
		queue_redraw()
		accept_event()


func _point_kind(p: Vector2) -> String:
	var r := _target_rect()
	var fx := (p.x - r.position.x) / r.size.x
	var fy := (p.y - r.position.y) / r.size.y
	var near_end := fx < 0.12 or fx > 0.88
	var near_edge := fy < 0.3 or fy > 0.7
	if near_end and near_edge:
		return "corner"
	if near_end or near_edge:
		return "edge"
	return "center"


func _draw() -> void:
	if stack == null or _done or index >= stack.height():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	draw_rect(_panel(), UIKit.PANEL)
	var font := get_theme_default_font()
	draw_string(font, _panel().position + Vector2(20, 32), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.ACCENT)
	var n := stack.count_above(index)
	draw_string(font, _panel().position + Vector2(20, 58), "上面压着 %d 份。%s" % [n, _hint], HORIZONTAL_ALIGNMENT_LEFT, 680, 15, UIKit.TEXT)
	# 桌面
	var table_y := _panel().end.y - 70
	draw_rect(Rect2(_panel().position.x + 100, table_y, BAR_W + 80, 10), Color("#8a6a4a"))
	# 上方的货随拉动被带着微微位移
	var drag := clampf(absf(_offset.x) / BAR_W, 0.0, 1.0)
	for i in stack.height():
		var r := _bar_rect(i)
		if i == index:
			continue
		if i > index:
			r = Rect2(r.position + Vector2(_offset.x * 0.08 * (i - index), drag * 2.0 * (i - index)), r.size)
		_draw_bar(r, stack.items[i].sku_id, false)
	_draw_bar(_target_rect(), stack.items[index].sku_id, true)
	if not _holding:
		var tr := _target_rect()
		for c in [tr.position, Vector2(tr.end.x, tr.position.y), Vector2(tr.position.x, tr.end.y), tr.end]:
			draw_circle(c, 4.0, Color(1, 1, 1, 0.5))


func _draw_bar(r: Rect2, sku_id: String, target: bool) -> void:
	draw_rect(r, UIKit.sku_color(sku_id))
	draw_rect(r, Color(1, 1, 1, 0.9 if target else 0.25), false, 2.0 if target else 1.0)
