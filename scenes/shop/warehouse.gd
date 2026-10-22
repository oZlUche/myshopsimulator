extends Control
## 仓库（07 §3）：托运部卸在门口的箱子搬去码放、拆箱看货、写标签，装上手推车拉去店里。
## 在仓库干活要花时间（每个动作、每一步路按耗时走表），没有客人。今天还没开始时可以摆仓库货架（不花时间）。

var s: GameState
var api: ActionAPI
var ops: RoomOps
var _view: RoomView
var _clock: Label
var _day: ProgressBar
var _cash: Label
var _closeup: HBoxContainer
var _carry: HBoxContainer
var _layout_box: VBoxContainer
var _layout_button: Button
var _shop_button: Button
var _log: RichTextLabel


func _ready() -> void:
	s = Game.state
	api = ActionAPI.new(s)
	_build()
	ops = RoomOps.new(s, ShopSetup.WAREHOUSE, _view, self, _say, _spend, _refresh)
	ops.ensure_cart()
	var door := s.inventory.room_cell(ShopSetup.WAREHOUSE, "door")
	ops.player_cell = door
	_view.place_player(door)
	_view.cell_clicked.connect(_on_cell)
	_view.cells_selected.connect(_on_cells)
	if Game.arrive_from == "shop":
		_say("推着车到了仓库。" if s.player.pushing_cart else "到仓库了。")
	else:
		_say("到仓库了。托运部把货卸在门口的黄框里。箱子外面只看得到物流单，拆开才知道里面是什么。")
	_say("点一堆箱子走过去，点最上面那箱：抱起来、拆箱、拿一包出来、写标签。抱着东西点别的格子空处就放下。")
	_say("在地上按住拉框可以一次抱起好几件（拿满为止）；手上有箱包时拉框是一格格放下去。")
	if ops.cart_here():
		_say("点手推车把它推起来：推着车时抱起的箱包直接放车上（一车 2 箱或 6 包，另有散货篓 %d 条），推去店里路上 %d 秒。" % [Inventory.CART_BASKET, int(ShopSetup.TRIP_SECONDS)])
	elif ops.cart() != null:
		_say("手推车停在店里。")
	if _day_over():
		_say("天已经黑了，回家吧。")
	_refresh()


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
	var top := UIKit.hbox(10)
	left.add_child(top)
	_clock = UIKit.label("", 18, UIKit.ACCENT)
	top.add_child(_clock)
	_day = ProgressBar.new()
	_day.custom_minimum_size = Vector2(180, 18)
	_day.max_value = 1.0
	_day.show_percentage = false
	_day.tooltip_text = "一旬的营业时间"
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#14151d")
	var fg := StyleBoxFlat.new()
	fg.bg_color = UIKit.ACCENT
	_day.add_theme_stylebox_override("background", bg)
	_day.add_theme_stylebox_override("fill", fg)
	top.add_child(_day)
	_cash = UIKit.label("", 18)
	top.add_child(_cash)
	_view = RoomView.new()
	_view.setup(s.inventory, ShopSetup.WAREHOUSE)
	_view.show_street = true
	_view.floor_kind = "concrete"
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.custom_minimum_size = Vector2(0, 300)
	left.add_child(_view)
	left.add_child(UIKit.label("近景（点地上或货架走过去；点最上面那个箱 / 包弹出能做的事，点空处把手上的放下）", 13, UIKit.MUTED))
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
	right.custom_minimum_size = Vector2(380, 0)
	root.add_child(right)
	_shop_button = UIKit.button("推车去店里 →", _go_shop, 20)
	right.add_child(_shop_button)
	var bar := UIKit.hbox(6)
	right.add_child(bar)
	_layout_button = UIKit.button("摆货架", _toggle_layout, 14)
	bar.add_child(_layout_button)
	bar.add_child(UIKit.button("今天到此为止", _go_home, 14))
	_layout_box = UIKit.vbox(6)
	_layout_box.visible = false
	right.add_child(_layout_box)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	right.add_child(_log)


func _process(dt: float) -> void:
	_view.step(dt)


func _say(t: String) -> void:
	_log.append_text(t + "\n")


func _day_over() -> bool:
	return s.clock.time_of_period >= 1.0


## 在仓库干活花时间；摆货架不花。
func _spend(seconds: float) -> void:
	if ops.layout_mode:
		return
	var was_over := _day_over()
	ShopSession.pass_time(s, seconds)
	if _day_over() and not was_over:
		_say("[color=#e05a4f]天黑了，今天就到这儿，回家吧。[/color]")


func _refresh() -> void:
	_clock.text = "%s　仓库%s" % [s.clock.label(), "（天黑了）" if _day_over() else ""]
	_day.value = s.clock.time_of_period
	_cash.text = "现金 %.1f" % s.player.cash
	_shop_button.disabled = _day_over()
	_layout_button.disabled = not ops.layout_mode and s.clock.time_of_period > 0.0
	_layout_button.text = "摆好了" if ops.layout_mode else "摆货架"
	ops.closeup(_closeup)
	ops.carry(_carry)
	_shop_button.text = "推车去店里 →" if s.player.pushing_cart else "去店里 →"
	_view.marks = []
	if ops.layout_mode:
		ops.layout_panel(_layout_box, _toggle_layout)
	_view.queue_redraw()


func _on_cell(c: Vector2i) -> void:
	if ops.layout_mode:
		ops.layout_click(c)
		_refresh()
		return
	if _day_over():
		_say("天黑了，回家吧。")
		return
	ops.focus_cell(c)
	_refresh()


## 地上拉框：一次抱起 / 放下几件箱包（07 §2.1）。
func _on_cells(cells: Array) -> void:
	if ops.layout_mode:
		return
	if _day_over():
		_say("天黑了，回家吧。")
		return
	ops.marquee(cells)
	_refresh()


func _on_slot(slot_id: String) -> void:
	if _day_over():
		_say("天黑了，回家吧。")
		return
	if not ops.put_from_hand(slot_id):
		if api.carrier().stack.height() > 0:
			_say("仓库里只放箱和包，散货拿回店里放。")
		else:
			_say("手上是空的。点最上面那箱 / 那包，抱起来再放到别处。")
	_refresh()


func _toggle_layout() -> void:
	if not ops.layout_mode and s.clock.time_of_period > 0.0:
		_say("摆货架要在今天开始之前。")
		return
	ops.set_layout(not ops.layout_mode)
	_layout_box.visible = ops.layout_mode
	_refresh()


func _go_shop() -> void:
	if ops.layout_mode:
		_toggle_layout()
	ShopSession.pass_time(s, ShopSetup.TRIP_SECONDS)
	if s.player.pushing_cart:
		s.player.cart_room = ShopSetup.SHOP
	s.inventory.prune_empty_floors(ShopSetup.WAREHOUSE)
	Game.arrive_from = "warehouse"
	Game.goto("shop")


func _go_home() -> void:
	if s.player.pushing_cart:
		ops.park_cart(true)
	s.inventory.prune_empty_floors(ShopSetup.WAREHOUSE)
	set_process(false)
	Game.end_period({"shop": true})
