extends "res://scenes/stall/stall.gd"
## 店面（07 §4）：开罗式斜视角的一间店，门口临街。
## 开门前（今天还没开始时）时间不走：摆设备、从货柜拿包拆到货架上。
## 开门后客人进来逛，到收银台问价；谈成了你走到货架把他要的那份拿回来交货（走路按格子算时间）。
## 关着门可以去仓库搬货（路上花时间，没有客人）；一旬的营业时间走完就打烊。
## 客人、讲价、交货全部沿用摆摊（StallSession），这里只换场地和走路。

var ops: RoomOps
var _view: ShopView
var _closeup: HBoxContainer
var _carry: HBoxContainer
var _layout_box: VBoxContainer
var _layout_button: Button
var _warehouse_button: Button
var _end_button: Button


func _ready() -> void:
	s = Game.state
	api = ActionAPI.new(s)
	session = ShopSession.new(s, Game.returning_for(s))
	session.passerby.connect(func(stayed): _view.add_walker(stayed))
	session.visitor_arrived.connect(_on_visitor_arrived)
	session.visitor_left.connect(_on_visitor_left)
	session.self_served.connect(_on_self_served)
	_build()
	ops = RoomOps.new(s, ShopSetup.SHOP, _view, self, _say, _spend, _refresh_all)
	var from_warehouse := Game.arrive_from == "warehouse"
	var start := s.inventory.room_cell(ShopSetup.SHOP, "door") if from_warehouse else ShopSetup.stand_cell(s.inventory)
	ops.player_cell = start
	_view.place_player(start)
	_view.cell_clicked.connect(_on_cell)
	_view.visitor_clicked.connect(_on_visitor_clicked)
	if s.clock.time_of_period >= 1.0:
		_close_shop_time()
	elif from_warehouse:
		_say("推着车回到店里。车停在门口，点手推车把东西搬下来。")
	else:
		_say("到店里了。开门前时间不走：点货柜走过去，把包拿起来，再点货架的空处，撕开倒上去。")
		_say("客人只看得到货架、橱窗和模特上的货；货柜里的客人看不到。点「摆设备」可以买、挪、卖设备。")
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

	var left := UIKit.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	_build_top(left)
	_view = ShopView.new()
	_view.setup(s.inventory, ShopSetup.SHOP)
	_view.session = session
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.custom_minimum_size = Vector2(0, 300)
	left.add_child(_view)
	_area = _view
	_view.cart_slot = null
	left.add_child(UIKit.label("近景（点地上或设备走过去；箱包点最上面那个弹出能做的事，点空处把手上的放下）", 13, UIKit.MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 196)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var row := UIKit.hbox(14)
	scroll.add_child(row)
	_closeup = UIKit.hbox(8)
	row.add_child(_closeup)
	row.add_child(VSeparator.new())
	_carry = UIKit.hbox(8)
	row.add_child(_carry)

	var right := UIKit.vbox(8)
	right.custom_minimum_size = Vector2(420, 0)
	root.add_child(right)
	_main_button = UIKit.button("开门营业", _on_main_button, 20)
	right.add_child(_main_button)
	var bar := UIKit.hbox(6)
	right.add_child(bar)
	_layout_button = UIKit.button("摆设备", _toggle_layout, 14)
	bar.add_child(_layout_button)
	_warehouse_button = UIKit.button("去仓库 →", _go_warehouse, 14)
	_warehouse_button.tooltip_text = "关门推车去仓库，路上 %d 秒" % int(ShopSetup.TRIP_SECONDS)
	bar.add_child(_warehouse_button)
	_end_button = UIKit.button("今天到此为止", _pack_up, 14)
	_end_button.tooltip_text = "打烊回家，结束这一旬"
	bar.add_child(_end_button)
	_layout_box = UIKit.vbox(6)
	_layout_box.visible = false
	right.add_child(_layout_box)
	right.add_child(UIKit.label("店里的客人（点问价的去讲价；谈成后把货拿到手上，点他交货）", 14, UIKit.MUTED))
	_visitor_box = UIKit.vbox(4)
	right.add_child(_visitor_box)
	var hp := UIKit.panel()
	right.add_child(hp)
	_haggle_box = UIKit.vbox(6)
	hp.add_child(_haggle_box)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	right.add_child(_log)


## 开门前、今天还没开始：时间不走。
func _frozen() -> bool:
	return phase == Phase.SETUP and s.clock.time_of_period <= 0.0


func _process(dt: float) -> void:
	if phase == Phase.OPEN and speed > 0.0 and _minigame == null:
		super._process(dt)
	else:
		_view.step(dt)


## 动手、走路要花时间：开着门时客人照常来；关着门、今天已经开始了，时间照走但没有客人。
func _spend(seconds: float) -> void:
	match phase:
		Phase.OPEN:
			session.tick(seconds)
		Phase.SETUP:
			if not _frozen():
				ShopSession.pass_time(s, seconds)
	if phase != Phase.CLOSED and s.clock.time_of_period >= 1.0:
		_close_shop_time()


## 店里不会"卖光自动收摊"：货架空了提醒补货。
func _check_goods(_real_dt: float) -> void:
	if phase != Phase.OPEN:
		return
	if session.table_empty():
		if not _table_empty_hinted:
			_table_empty_hinted = true
			_say("货架上空了。去货柜拿包拆上来，或者关门去仓库搬货。")
	else:
		_table_empty_hinted = false


# ---------- 刷新 ----------
func _refresh_header() -> void:
	var state_txt := ""
	match phase:
		Phase.SETUP:
			state_txt = "开门前（时间暂停）" if _frozen() else "关着门"
		Phase.OPEN:
			state_txt = "营业中" if speed > 0 else "已暂停"
		Phase.CLOSED:
			state_txt = "打烊了"
	_clock.text = "%s　%s" % [s.clock.label(), state_txt]
	_day.value = s.clock.time_of_period
	_cash.text = "现金 %.1f" % s.player.cash
	_speed_box.visible = phase == Phase.OPEN
	_layout_button.disabled = not _frozen()
	_layout_button.text = "摆设备" if not ops or not ops.layout_mode else "摆好了"
	_warehouse_button.disabled = phase == Phase.CLOSED or _haggle != null
	_end_button.disabled = _haggle != null


func _refresh_slots() -> void:
	if ops == null:
		return
	session.refresh_layout()
	ops.closeup(_closeup, _highlight_item())
	ops.carry(_carry)
	_view.cart_slot = ops.cart()
	_view.cart_g = ops.cart_foot() if ops.cart() != null else Vector2(-99, -99)
	_update_marks()
	if ops.layout_mode:
		ops.layout_panel(_layout_box, _toggle_layout)
	_view.queue_redraw()


## 全景里亮框：客人要的那份在哪个设备上（金色），门口走不到的设备（红色）。
func _update_marks() -> void:
	var marks := ops.blocked_marks()
	for v in session.visitors:
		if v["state"] in ["haggling", "waiting_item"] and v.get("item_id", "") != "":
			var cell := _item_cell(v["item_id"])
			if cell.x >= 0:
				marks.append({"cell": cell, "color": UIKit.ACCENT})
	_view.marks = marks


func _item_cell(item_id: String) -> Vector2i:
	var at := session.locate(item_id)
	if at.is_empty():
		return Vector2i(-1, -1)
	var sl: Slot = s.inventory.slots[at["slot_id"]]
	var e: Dictionary = s.inventory.equipment.get(sl.equipment_id, {})
	if not e.has("pos"):
		return Vector2i(-1, -1)
	return Vector2i(int(e["pos"][0]), int(e["pos"][1]))


func _pointing_text() -> String:
	var at := session.locate(_haggle_visitor.get("item_id", ""))
	if at.is_empty():
		return "他要的那份不在货架上了。"
	return "他要「%s」里白框那份（亮金框）。" % session.slot_title(s.inventory.slots[at["slot_id"]])


# ---------- 走动、动手 ----------
func _on_cell(c: Vector2i) -> void:
	if ops.layout_mode:
		ops.layout_click(c)
		_refresh_all()
		return
	if _haggle != null:
		_say("先把这单谈完。")
		return
	ops.focus_cell(c)
	_refresh_all()


func _on_slot(slot_id: String) -> void:
	if ops.put_from_hand(slot_id):
		_refresh_all()
		return
	super._on_slot(slot_id)


func _on_top(slot_id: String) -> void:
	if not _hand().packages.is_empty() and slot_id != _hand().id:
		_say("手上抱着箱包，先放下才能拿散货。")
		return
	super._on_top(slot_id)


func _on_strip(slot_id: String, index: int) -> void:
	if not _hand().packages.is_empty() and slot_id != _hand().id:
		_say("手上抱着箱包，先放下才能拿散货。")
		return
	super._on_strip(slot_id, index)


## 讲价、交货都在收银台：人不在就先走回去（按格子花时间，客人那边时间照走）。
func _back_to_counter() -> bool:
	var stand := ShopSetup.stand_cell(s.inventory)
	if ops.player_cell == stand:
		return true
	return ops.walk_to(stand, true)


func _start_haggle(v: Dictionary) -> void:
	if _haggle != null:
		return
	if not _back_to_counter():
		return
	if v["state"] != "asking":
		_say("#%d 等不及，已经走了。" % _view.visitor_numbers.get(v["customer"].id, 0))
		_refresh_all()
		return
	super._start_haggle(v)


func _deliver(v: Dictionary) -> void:
	if not _back_to_counter():
		return
	if v["state"] != "waiting_item":
		_say("#%d 已经走了。" % _view.visitor_numbers.get(v["customer"].id, 0))
		_refresh_all()
		return
	super._deliver(v)


# ---------- 摆设备 ----------
func _toggle_layout() -> void:
	if not ops.layout_mode and not _frozen():
		_say("摆设备要在开门前（今天还没开始的时候）。")
		return
	ops.set_layout(not ops.layout_mode)
	_layout_box.visible = ops.layout_mode
	if ops.layout_mode:
		_say("摆设备：时间不走。门口到每件设备都要留出路来。")
	_refresh_all()


# ---------- 开门 / 关门 / 去仓库 / 打烊 ----------
func _on_main_button() -> void:
	match phase:
		Phase.SETUP:
			if session.table_empty():
				_say("货架上什么都没摆呢。先从货柜里拿包，倒到货架上。")
				return
			if ops.layout_mode:
				_toggle_layout()
			phase = Phase.OPEN
			_main_button.text = "关门"
			_say("开门了！")
		Phase.OPEN:
			if _haggle != null:
				_say("先把这单谈完。")
				return
			session.close()
			phase = Phase.SETUP
			_main_button.text = "开门营业"
			_say("关上门，店里的客人都走了。")
		Phase.CLOSED:
			_pack_up()
	_refresh_all()


func _close_shop_time() -> void:
	if phase == Phase.OPEN:
		session.close()
	phase = Phase.CLOSED
	_main_button.text = "打烊回家"
	_say("天黑了，打烊。")
	_refresh_all()


func _go_warehouse() -> void:
	if _haggle != null:
		_say("先把这单谈完。")
		return
	if ops.layout_mode:
		_toggle_layout()
	if phase == Phase.OPEN:
		session.close()
	ShopSession.pass_time(s, ShopSetup.TRIP_SECONDS)
	_leave()
	Game.arrive_from = "shop"
	Game.goto("warehouse")


func _pack_up(_sold_out := false) -> void:
	if _haggle != null:
		_say("先把手上这单谈完。")
		return
	if phase == Phase.OPEN:
		session.close()
	phase = Phase.CLOSED
	_leave()
	Game.end_period({"shop": true})


## 离开店面：空地堆格清掉，没回来的常客留给下一次进店。
func _leave() -> void:
	s.inventory.prune_empty_floors(ShopSetup.SHOP)
	Game.keep_returning(session.returning_left())
	set_process(false)
