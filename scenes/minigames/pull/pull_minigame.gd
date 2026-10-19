class_name PullMinigame
extends Control
## 抽取小游戏（03 §2.1）：侧面看货堆，按住目标货的发力点拖出来。
## 最佳：按角落、斜向 30°–45°、先慢后快。上方越重，货越"跟不上手"。
## 货抽出多少就停在多少，不会缩回；可以分几次拉，累计抽出一半就算抽出来了。
## 每段拖动轨迹各自换算成偏差分，按这段拉出的距离加权平均，交给 ActionAPI 走统一的倒塌结算。

## success 时 pull_input 为 {d}；progress 为 {out, d_sum, w_sum, shift}，调用方经 ActionAPI 记下（不论成败）。
signal finished(success: bool, pull_input: Dictionary, seconds: float, progress: Dictionary)

const BAR_W := 360.0
const BAR_H := 24.0

var stack: ItemStack
var index: int
var title := ""

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
var _d_sum := 0.0
var _w_sum := 0.0
## 这次打开以来目标被带着横移的累计（传给上方的货）
var _shift := 0.0
var _seg_start := 0.0
## 按住时货被微微抬起（只是手感，松手就落回去）
var _lift := 0.0
var _base_shift: Array[float] = []


func setup(st: ItemStack, idx: int, t: String) -> PullMinigame:
	stack = st
	index = idx
	title = t
	mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.full_rect(self)
	var it: ScarfItem = st.items[idx]
	_out = it.pull_out
	_d_sum = it.pull_d_sum
	_w_sum = it.pull_w_sum
	for x in st.items:
		_base_shift.append(x.shift)
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


func _bar_rect(i: int) -> Rect2:
	var base := Vector2(_panel().position.x + 180, _panel().end.y - 70)
	return Rect2(base.x, base.y - (i + 1) * BAR_H, BAR_W, BAR_H - 2)


func progress() -> Dictionary:
	return {"out": _out, "d_sum": _d_sum, "w_sum": _w_sum, "shift": _shift}


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
		# 货只能顺着已经抽出的方向往外走，往回推不动（不会缩回）
		var dx := step.x / BAR_W
		if _out != 0.0 and signf(dx) != signf(_out):
			dx = 0.0
		_out = clampf(_out + dx, -ActionAPI.PULL_DONE, ActionAPI.PULL_DONE)
		_shift += dx
		# 往上带一点，往下压不动
		_lift = clampf(_lift + minf(step.y, 0.0), -BAR_H * 0.5, 0.0)
	queue_redraw()
	if absf(_out) >= ActionAPI.PULL_DONE:
		_end_segment()
		_done = true
		finished.emit(true, {"d": _d_sum / maxf(_w_sum, 0.001)}, _elapsed, progress())


## 一次按住到松手算一段：这段的手法偏差按这段拉出的距离计权。
func _end_segment() -> void:
	if not _holding:
		return
	_holding = false
	_lift = 0.0
	var w := absf(_out - _seg_start)
	if w > 0.0:
		_d_sum += PullPhysics.deviation_from_input(PullPhysics.input_from_drag(_samples, _point)) * w
		_w_sum += w


func _stop() -> void:
	if _done:
		return
	_end_segment()
	_done = true
	finished.emit(false, {}, _elapsed, progress())


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
			_end_segment()
			_hint = "松手了，货停在抽出 %d%% 的地方。接着拉，或者先停手。" % roundi(absf(_out) * 100.0)
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
	# 上方的货被带歪的位置一直保留
	for i in stack.height():
		if i == index:
			continue
		var sh := _base_shift[i]
		if i > index:
			sh = clampf(sh + _shift * ActionAPI.ABOVE_DRAG * (i - index), -ActionAPI.MAX_SHIFT, ActionAPI.MAX_SHIFT)
		var r := _bar_rect(i)
		_draw_bar(Rect2(r.position + Vector2(sh * BAR_W, 0), r.size), stack.items[i].sku_id, false)
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
