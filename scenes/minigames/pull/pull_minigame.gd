class_name PullMinigame
extends Control
## 抽取小游戏（03 §2.1）：正面看货堆，按住目标货的发力点拖出来。
## 最佳：按角落、斜向 30°–45°、先慢后快。上方越重，货越"跟不上手"。
## 货抽出多少就停在多少，不会缩回；可以分几次拉，累计抽出一半就算抽出来了。
## 每段（按住到松手）各自换算成偏差分，经 ActionAPI.pull_segment 单独掷一次倒塌 / 位移判定。

## result: {resolved: true, out, collapsed, displaced}。success 时直接交给 ActionAPI 取货（判定已经掷过）。
signal finished(success: bool, result: Dictionary, seconds: float)

const BAR_W := 360.0
const BAR_H := 24.0

var stack: ItemStack
var index: int
var title := ""
var api: ActionAPI
var slot_id := ""

var _holding := false
var _point := "center"
var _samples: Array = []
var _last_mouse := Vector2.ZERO
var _elapsed := 0.0
var _hint := ""
var _cancel: Button
var _done := false
## 已抽出的比例（±，占货长），只增不减
var _out := 0.0
var _seg_start := 0.0
## 这一段把目标横向带动了多少（松手时交给 ActionAPI 传给上方的货）
var _seg_shift := 0.0
var _collapsed := false
var _displaced := false
## 按住时货被微微抬起（只是手感，松手就落回去）
var _lift := 0.0


func setup(action_api: ActionAPI, sl_id: String, idx: int, t: String) -> PullMinigame:
	api = action_api
	slot_id = sl_id
	stack = api.s.inventory.slots[sl_id].stack
	index = idx
	title = t
	mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.full_rect(self)
	_out = stack.items[idx].pull_out
	_hint = "按住白框那份货的一角，斜着往外拉，先慢后快。" if _out == 0.0 \
		else "上次已经抽出 %d%%，接着拉。" % roundi(absf(_out) * 100.0)
	return self


func _ready() -> void:
	_cancel = UIKit.button("先停手", _stop)
	add_child(_cancel)
	resized.connect(_place_cancel)
	_place_cancel.call_deferred()


func _place_cancel() -> void:
	_cancel.position = _panel().end - _cancel.size - Vector2(16, 16)


func _panel() -> Rect2:
	return Rect2(size * 0.5 - Vector2(360, 200), Vector2(720, 400))


func _target_rect() -> Rect2:
	var r := _bar_rect(index)
	return Rect2(r.position + Vector2(_out * BAR_W, _lift), r.size)


## 第 i 份货的位置：按它实际所在的层画（下面被抽空的层留着空隙）。
func _bar_rect(i: int) -> Rect2:
	var base := Vector2(_panel().position.x + 180, _panel().end.y - 70)
	var layer := stack.layer_of(i)
	return Rect2(base.x, base.y - (layer + 1) * BAR_H, BAR_W, BAR_H - 2)


func result() -> Dictionary:
	return {"resolved": true, "out": _out, "collapsed": _collapsed, "displaced": _displaced}


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
		var step := hand.normalized() * v_item * dt
		# 货沿着抽出的方向走，手往外拖多远（按跟手比例打折）它就出来多远；
		# 只要一直拖就一定能带出，手法差只是更慢、更容易塌（03 §2.0）。往回推不动，不会缩回。
		var dir := signf(_out) if _out != 0.0 else signf(hand.x)
		var dx := 0.0
		if dir != 0.0 and signf(hand.x) != -dir:
			dx = dir * v_item * dt / BAR_W
		_out = clampf(_out + dx, -ActionAPI.PULL_DONE, ActionAPI.PULL_DONE)
		_seg_shift += dx
		# 往上带一点，往下压不动
		_lift = clampf(_lift + minf(step.y, 0.0), -BAR_H * 0.5, 0.0)
	queue_redraw()
	if absf(_out) >= ActionAPI.PULL_DONE:
		_end_segment()
		_done = true
		finished.emit(true, result(), _elapsed)


## 一次按住到松手算一段：这段的手法单独掷一次倒塌 / 位移判定，进度记进货堆。
func _end_segment() -> void:
	if not _holding:
		return
	_holding = false
	_lift = 0.0
	if _out == _seg_start:
		return
	var d := PullPhysics.deviation_from_input(PullPhysics.input_from_drag(_samples, _point))
	var res := api.pull_segment(slot_id, index, _out, d, _seg_shift)
	_seg_shift = 0.0
	if res["collapsed"]:
		_collapsed = true
		_hint = "上面的货塌了，掉了一地！这份还露在外面。"
	elif res["displaced"]:
		_displaced = true


func _stop() -> void:
	if _done:
		return
	_end_segment()
	_done = true
	finished.emit(false, result(), _elapsed)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _target_rect().has_point(e.position):
			_holding = true
			_point = _point_kind(e.position)
			_samples = [{"t": _elapsed, "pos": e.position}]
			_last_mouse = e.position
			_seg_start = _out
			_hint = {"corner": "抓住了角。", "edge": "抓在边上，不太好使力。", "center": "抓在中间，很难带出来。"}[_point]
		elif not e.pressed and _holding:
			_hint = "松手了，货停在抽出 %d%% 的地方。接着拉，或者先停手。" % roundi(absf(_out) * 100.0)
			_end_segment()
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
	draw_rect(Rect2(_panel().position.x + 140, table_y, BAR_W + 80, 10), Color("#8a6a4a"))
	# 上方的货被带歪的位置一直保留；这一段正在带动的部分先画出来，松手后记进货堆
	for i in stack.height():
		if i == index:
			continue
		var sh := stack.items[i].shift
		if i > index:
			sh = clampf(sh + _seg_shift * ActionAPI.ABOVE_DRAG * (i - index), -ActionAPI.MAX_SHIFT, ActionAPI.MAX_SHIFT)
		var r := _bar_rect(i)
		_draw_bar(Rect2(r.position + Vector2(sh * BAR_W, 0), r.size), stack.items[i].sku_id, false)
	for i in stack.collapsed_pile.size():
		var pr := Rect2(_panel().position.x + 150 + (i % 6) * 64.0, table_y + 12 + floorf(i / 6.0) * 8.0, 56, 8)
		draw_rect(pr, UIKit.sku_color(stack.collapsed_pile[i].sku_id))
	var tr := _target_rect()
	_draw_bar(tr, stack.items[index].sku_id, true)
	# 抽出进度：过了虚线就算抽出来了
	var home := _bar_rect(index)
	var dir := -1.0 if _out < 0.0 else 1.0
	var goal_x := home.position.x + (home.size.x if dir > 0.0 else 0.0) + dir * ActionAPI.PULL_DONE * BAR_W
	draw_dashed_line(Vector2(goal_x, home.position.y - 30), Vector2(goal_x, table_y), UIKit.ACCENT, 2.0, 6.0)
	if _out == 0.0:
		var other_x := home.position.x - ActionAPI.PULL_DONE * BAR_W
		draw_dashed_line(Vector2(other_x, home.position.y - 30), Vector2(other_x, table_y), UIKit.ACCENT, 2.0, 6.0)
	draw_string(font, Vector2(home.position.x, table_y + 34), "已抽出 %d%% / 需要 %d%%" % [roundi(absf(_out) * 100.0), roundi(ActionAPI.PULL_DONE * 100.0)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.MUTED)
	if not _holding:
		for c in [tr.position, Vector2(tr.end.x, tr.position.y), Vector2(tr.position.x, tr.end.y), tr.end]:
			draw_circle(c, 4.0, Color(1, 1, 1, 0.5))


func _draw_bar(r: Rect2, sku_id: String, target: bool) -> void:
	draw_rect(r, UIKit.sku_color(sku_id))
	draw_rect(r, Color(1, 1, 1, 0.9 if target else 0.25), false, 2.0 if target else 1.0)
