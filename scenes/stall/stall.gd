extends Control
## 摆摊营业（01 §6.9）：先摆货（时间不走），开张后实时推进；客人问价时去议价。
## 只读认知层：客人信息来自【客人观察】采样，货堆只看得到边缘颜色。

enum Phase { SETUP, OPEN, CLOSED }

var s: GameState
var api: ActionAPI
var session: StallSession
var phase := Phase.SETUP
var speed := 1.0

var _clock: Label
var _day: ProgressBar
var _cash: Label
var _area: AreaView
var _table_box: HBoxContainer
var _bag_box: HBoxContainer
var _visitor_box: VBoxContainer
var _haggle_box: VBoxContainer
var _log: RichTextLabel
var _main_button: Button
var _speed_box: HBoxContainer

var _selected := {"slot_id": "", "index": -1}
var _haggle: HaggleState
var _haggle_visitor: Dictionary = {}
var _next_number := 1
var _price_spin: SpinBox
var _minigame: PullMinigame


func _ready() -> void:
	s = Game.state
	api = ActionAPI.new(s)
	session = StallSession.new(s, Game.stall_x)
	session.passerby.connect(func(stayed): _area.add_walker(stayed))
	session.visitor_arrived.connect(_on_visitor_arrived)
	session.visitor_left.connect(_on_visitor_left)
	_build()
	_say("找好位置了。先把行囊里的货摆到摊位上（左键选中一份，再点摊位格的空处），然后开张。时间还没开始走。")
	_refresh_all()


func _build() -> void:
	UIKit.background(self)
	var root := UIKit.hbox(12)
	UIKit.full_rect(root)
	root.offset_left = 12
	root.offset_right = -12
	root.offset_top = 10
	root.offset_bottom = -10
	add_child(root)

	var left := UIKit.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var top := UIKit.hbox(10)
	left.add_child(top)
	_clock = UIKit.label("", 18, UIKit.ACCENT)
	top.add_child(_clock)
	_day = ProgressBar.new()
	_day.custom_minimum_size = Vector2(180, 18)
	_day.max_value = 1.0
	_day.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#14151d")
	var fg := StyleBoxFlat.new()
	fg.bg_color = UIKit.ACCENT
	_day.add_theme_stylebox_override("background", bg)
	_day.add_theme_stylebox_override("fill", fg)
	_day.tooltip_text = "一旬的营业时间"
	top.add_child(_day)
	_cash = UIKit.label("", 18)
	top.add_child(_cash)
	_speed_box = UIKit.hbox(4)
	top.add_child(_speed_box)
	for spec in [["暂停", 0.0], ["1x", 1.0], ["2x", 2.0], ["3x", 3.0]]:
		_speed_box.add_child(UIKit.button(spec[0], func(): speed = spec[1]; _refresh_header(), 14))
	_speed_box.add_child(UIKit.label("流速", 13, UIKit.MUTED))
	var flow := HSlider.new()
	flow.min_value = 0.25
	flow.max_value = 4.0
	flow.step = 0.25
	flow.value = Game.time_scale
	flow.custom_minimum_size = Vector2(90, 0)
	flow.tooltip_text = "时间流速（设置项）"
	flow.value_changed.connect(func(v): Game.time_scale = v; _refresh_header())
	_speed_box.add_child(flow)

	_area = AreaView.new()
	_area.session = session
	_area.custom_minimum_size = Vector2(0, 240)
	left.add_child(_area)

	left.add_child(UIKit.label("摊位（从正面只看得到每份货露出的边缘颜色；右键翻看，悬停看记忆）", 13, UIKit.MUTED))
	_table_box = UIKit.hbox(8)
	left.add_child(_table_box)
	left.add_child(UIKit.label("行囊", 13, UIKit.MUTED))
	_bag_box = UIKit.hbox(8)
	left.add_child(_bag_box)

	var right := UIKit.vbox(8)
	right.custom_minimum_size = Vector2(420, 0)
	root.add_child(right)
	_main_button = UIKit.button("开张！", _on_main_button, 20)
	right.add_child(_main_button)
	right.add_child(UIKit.label("在摊前的客人（点问价的客人去议价）", 14, UIKit.MUTED))
	_visitor_box = UIKit.vbox(4)
	right.add_child(_visitor_box)
	var hp := UIKit.panel()
	right.add_child(hp)
	_haggle_box = UIKit.vbox(6)
	hp.add_child(_haggle_box)
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	right.add_child(_log)


func _process(dt: float) -> void:
	if phase != Phase.OPEN or speed <= 0.0 or _minigame != null:
		_area.step(0.0)
		return
	var sdt := dt * speed * Game.time_scale
	session.tick(sdt)
	_area.step(sdt)
	if session.is_over():
		_close_shop_time()
	_refresh_header()
	_refresh_visitors()


func _say(t: String) -> void:
	_log.append_text(t + "\n")


# ---------- 刷新 ----------
func _refresh_all() -> void:
	_refresh_header()
	_refresh_slots()
	_refresh_visitors()
	_refresh_haggle()


func _refresh_header() -> void:
	var state_txt: String = {Phase.SETUP: "摆货中（时间暂停）", Phase.OPEN: "营业中" if speed > 0 else "已暂停", Phase.CLOSED: "天黑了"}[phase]
	_clock.text = "%s　%s" % [s.clock.label(), state_txt]
	_day.value = s.clock.time_of_period
	_cash.text = "现金 %.1f" % s.player.cash


func _refresh_slots() -> void:
	var highlight := ""
	if not _haggle_visitor.is_empty():
		highlight = _haggle_visitor["item_id"]
	for pair in [[_table_box, "StallTable", "摊位"], [_bag_box, "Bag", "行囊"]]:
		var box: HBoxContainer = pair[0]
		UIKit.clear(box)
		var n := 1
		for sl in s.inventory.slots_of_type(pair[1]):
			var v := StackView.new().setup(sl, "%s %d" % [pair[2], n])
			n += 1
			v.highlight_item_id = highlight
			if sl.id == _selected["slot_id"]:
				v.selected_index = _selected["index"]
			v.strip_pressed.connect(_on_strip)
			v.strip_peek.connect(_on_peek)
			v.slot_pressed.connect(_on_slot)
			v.pile_pressed.connect(_on_pile)
			box.add_child(v)


func _refresh_visitors() -> void:
	# 只在名单变化时重建，避免每帧重建按钮
	var sig := ""
	for v in session.visitors:
		sig += "%s:%s:%d|" % [v["customer"].id, v["state"], int(float(v["wait"]))]
	if _visitor_box.get_meta("sig", "") == sig:
		return
	_visitor_box.set_meta("sig", sig)
	UIKit.clear(_visitor_box)
	if session.visitors.is_empty():
		_visitor_box.add_child(UIKit.label("（暂时没人）", 14, UIKit.MUTED))
	for v in session.visitors:
		var num: int = _area.visitor_numbers.get(v["customer"].id, 0)
		var regular := "（常客）" if v["customer"].is_regular else ""
		match v["state"]:
			"asking":
				var b := UIKit.button("#%d%s 在问价，还能等 %d 秒 → 去招呼" % [num, regular, int(float(v["wait"]))], func(): _start_haggle(v), 14)
				b.disabled = _haggle != null
				_visitor_box.add_child(b)
			"haggling":
				_visitor_box.add_child(UIKit.label("#%d%s 正在跟你讲价" % [num, regular], 14, Color("#6fa8dc")))
			_:
				_visitor_box.add_child(UIKit.label("#%d%s 在看货" % [num, regular], 14, UIKit.MUTED))


# ---------- 摆货 ----------
func _on_strip(slot_id: String, index: int) -> void:
	if _selected["slot_id"] == slot_id and _selected["index"] == index:
		_selected = {"slot_id": "", "index": -1}
	else:
		_selected = {"slot_id": slot_id, "index": index}
	_refresh_slots()


func _on_slot(slot_id: String) -> void:
	if _selected["slot_id"] == "" or _selected["slot_id"] == slot_id:
		return
	var from: String = _selected["slot_id"]
	var idx: int = _selected["index"]
	_with_pull(from, idx, func(input): _do_move(from, idx, slot_id, input))


func _do_move(from: String, idx: int, slot_id: String, input: Dictionary) -> void:
	var r := api.move_item(from, idx, slot_id, input)
	if not r["ok"]:
		_say("放不下了。")
	elif r["collapsed"]:
		_say("[color=#e05a4f]抽的时候上面的货塌了，掉了一地！点地上那堆可以拾起来。[/color]")
	elif r["displaced"]:
		_say("上面那几份被带歪了。")
	_selected = {"slot_id": "", "index": -1}
	_spend(1.5)
	_refresh_slots()


func _on_peek(slot_id: String, index: int) -> void:
	var p := api.peek_item(slot_id, index)
	if p.is_empty():
		return
	var name := UIKit.sku_name(p["sku_guess"])
	_say("掀起一角看了看：像是%s%s。" % [name, "（图案款，可能看错）" if p["may_be_wrong"] else ""])
	_spend(2.0)
	_refresh_slots()


func _on_pile(slot_id: String) -> void:
	var n := api.pick_up_pile(slot_id)
	_say("拾起了 %d 份放回堆顶。" % n if n > 0 else "堆满了，放不回去。")
	_spend(1.0 + n)
	_refresh_slots()


## 从堆下面抽货要玩抽取小游戏；顶上的、行囊里的直接拿。then(input) 在拿到之后调用。
func _with_pull(slot_id: String, index: int, then: Callable) -> void:
	var sl: Slot = s.inventory.slots[slot_id]
	if index >= sl.stack.height() - 1 or not ActionAPI.PHYSICS_SLOT_TYPES.has(sl.type):
		then.call(ActionAPI.CAREFUL_PULL)
		return
	_minigame = PullMinigame.new().setup(sl.stack, index, "从堆里抽出这份")
	add_child(_minigame)
	_minigame.finished.connect(func(ok, input, seconds):
		_minigame.queue_free()
		_minigame = null
		_spend(seconds)
		if ok:
			then.call(input)
		else:
			_say("没抽。")
			_refresh_all())


## 动手干活要花时间（营业中才算）。
func _spend(seconds: float) -> void:
	if phase == Phase.OPEN:
		session.tick(seconds)


# ---------- 客人与议价 ----------
func _on_visitor_arrived(v: Dictionary) -> void:
	_area.visitor_numbers[v["customer"].id] = _next_number
	_next_number += 1


func _on_visitor_left(v: Dictionary) -> void:
	if v == _haggle_visitor:
		return


func _start_haggle(v: Dictionary) -> void:
	if _haggle != null:
		return
	var h := session.start_haggle(v)
	if h == null:
		_say("#%d 看中的那份没了，摊上也没别的合意的，走了。" % _area.visitor_numbers.get(v["customer"].id, 0))
		session.finish(v, null)
		return
	_haggle = h
	_haggle_visitor = v
	_refresh_all()


func _refresh_haggle() -> void:
	UIKit.clear(_haggle_box)
	if _haggle == null:
		_haggle_box.add_child(UIKit.label("议价", 16, UIKit.ACCENT))
		_haggle_box.add_child(UIKit.label("有客人问价时点他，在这里讲价。", 14, UIKit.MUTED))
		return
	var c := _haggle.customer
	var num: int = _area.visitor_numbers.get(c.id, 0)
	_haggle_box.add_child(UIKit.label("客人 #%d%s" % [num, "（常客）" if c.is_regular else ""], 16, UIKit.ACCENT))
	var hint := Sampler.customer_hint(c, s.player, _haggle.sku_id)
	var hint_lines: Array = []
	for key in ["preference", "patience", "budget", "strategy", "loyalty"]:
		if hint.has(key):
			hint_lines.append({"preference": "喜好", "patience": "耐心", "budget": "预算", "strategy": "性格", "loyalty": "回头"}[key] + "：" + hint[key])
	if hint_lines.is_empty():
		hint_lines.append("（看不出这人的心思。学【客人观察】能看得更多。）")
	for l in hint_lines:
		_haggle_box.add_child(UIKit.label(l, 13, UIKit.MUTED))
	_haggle_box.add_child(UIKit.label("他指着摊上白框那份。你的开价：%d 元" % roundi(_haggle.asking_price), 14))
	_haggle_box.add_child(UIKit.label("「%s」" % _haggle.last_line, 18))
	if _haggle.result != "ongoing":
		_haggle_box.add_child(UIKit.button("好", _end_haggle))
		return
	var row := UIKit.hbox(6)
	_price_spin = SpinBox.new()
	_price_spin.min_value = 1
	_price_spin.max_value = 9999
	_price_spin.value = roundf(maxf(_haggle.customer_offer + 1.0, (_haggle.asking_price + _haggle.customer_offer) * 0.5))
	row.add_child(_price_spin)
	row.add_child(UIKit.button("报这个价", func(): _haggle.offer_price(_price_spin.value, s.rng); _after_haggle_step(), 14))
	_haggle_box.add_child(row)
	_haggle_box.add_child(UIKit.button("就按 %d 元卖给你" % roundi(_haggle.customer_offer), func(): _haggle.accept_customer_offer(); _after_haggle_step(), 14))
	for id in HaggleState.OPTIONS:
		_haggle_box.add_child(UIKit.button("「%s」" % HaggleState.OPTIONS[id], func(): _haggle.choose_option(id, s.rng); _after_haggle_step(), 14))


func _after_haggle_step() -> void:
	_spend(3.0)
	_refresh_haggle()


func _end_haggle() -> void:
	if _haggle.result == "deal":
		var loc := session.locate(_haggle_visitor["item_id"])
		if not loc.is_empty():
			_with_pull(loc["slot_id"], loc["index"], func(input): _finish_haggle(input))
			return
	_finish_haggle(ActionAPI.CAREFUL_PULL)


func _finish_haggle(input: Dictionary) -> void:
	var r := session.finish(_haggle_visitor, _haggle, input)
	if _haggle.result == "deal":
		if r.get("ok", false):
			_say("[color=#6cc070]卖出一条，收 %d 元。[/color]" % roundi(_haggle.final_price))
			if r.get("collapsed", false):
				_say("[color=#e05a4f]从下面抽的时候上面的货塌了！[/color]")
		else:
			_say("那份货找不着了，这单没做成。")
	_haggle = null
	_haggle_visitor = {}
	_refresh_all()


# ---------- 开张 / 收摊 ----------
func _on_main_button() -> void:
	match phase:
		Phase.SETUP:
			if s.inventory.count_items("", "StallTable") == 0:
				_say("摊上什么都没摆呢。")
				return
			phase = Phase.OPEN
			_main_button.text = "提前收摊"
			_say("开张了！")
		Phase.OPEN, Phase.CLOSED:
			_pack_up()
	_refresh_header()


func _close_shop_time() -> void:
	phase = Phase.CLOSED
	_main_button.text = "收摊回家"
	_say("天色晚了，路上没什么人了。")


func _pack_up() -> void:
	if _haggle != null:
		_say("先把手上这单谈完。")
		return
	var lost := api.pack_up()
	if lost > 0:
		_say("行囊装不下，%d 份只能扔了。" % lost)
	Game.end_period({"lost_on_pack_up": lost})
