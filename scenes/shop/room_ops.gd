class_name RoomOps
extends RefCounted
## 店面和仓库共用的"动手"（07 §2–§4）：点一格走过去、近景面板（那格上的货位 + 手上 + 手推车）、
## 箱包菜单（抱起、拆箱、拿一包、看一眼、写标签…）、把手上的东西放下、摆设备。
## 花多少时间、说什么、怎么刷新交给场景给的回调；规则都在 ActionAPI / RoomGrid。

var s: GameState
var api: ActionAPI
var loc: String
var view: RoomView
var host: Control
var say: Callable       # (text: String)
var spend: Callable     # (seconds: float)
var refresh: Callable   # ()
## 玩家站在哪格
var player_cell := Vector2i(0, 0)
## 近景里看的是哪格（-1 = 还没选）
var focus := Vector2i(-1, -1)
## 摆设备模式：选中的设备种类 / 正在挪的设备 / 点中的设备
var layout_mode := false
var placing_def := ""
var picked_eid := ""


func _init(state: GameState, location_id: String, room_view: RoomView, host_node: Control,
		say_cb: Callable, spend_cb: Callable, refresh_cb: Callable) -> void:
	s = state
	api = ActionAPI.new(state)
	loc = location_id
	view = room_view
	host = host_node
	say = say_cb
	spend = spend_cb
	refresh = refresh_cb


func inv() -> Inventory:
	return s.inventory


func cart() -> Slot:
	var carts := inv().slots_of_type("Cart")
	return carts[0] if not carts.is_empty() else null


## 手推车停在门口外面（画在门外那一溜上）。
func cart_foot() -> Vector2:
	var door := inv().room_cell(loc, "door")
	return Vector2(door.x + 1.5, inv().room_size(loc).y + 0.55)


# ---------- 走路 ----------
## 走到 c 旁边（onto = 走到 c 上面）；c 上是设备就走到它开口那一侧（站得过去的话）。
## 走路按步数花时间，路被堵住就走不过去。
func walk_to(c: Vector2i, onto := false) -> bool:
	var p: Array[Vector2i] = []
	if not onto and inv().equipment_at(loc, c) != "":
		var f := RoomGrid.front(inv(), loc, c)
		if RoomGrid.walkable(inv(), loc, f):
			p = RoomGrid.path(inv(), loc, player_cell, f, true)
	if p.is_empty():
		p = RoomGrid.path(inv(), loc, player_cell, c, onto)
	if p.is_empty():
		say.call("[color=#e05a4f]走不过去，路被挡住了。[/color]")
		return false
	if p.size() > 1:
		view.follow_path(p)
		spend.call(RoomGrid.STEP_SECONDS * (p.size() - 1))
	player_cell = p[-1]
	return true


## 点地上或设备：走过去，近景面板换成那一格。
func focus_cell(c: Vector2i) -> bool:
	if not walk_to(c):
		return false
	focus = c
	view.selected_cell = c
	return true


## 手推车在门口：要用它得先走到门口。
func walk_to_cart() -> bool:
	return walk_to(inv().room_cell(loc, "door"), true)


# ---------- 近景面板 ----------
## 选中那格上的货位：设备的每一格，或者地上那一堆。
func closeup(box: HBoxContainer, highlight := "") -> void:
	UIKit.clear(box)
	if not RoomGrid.in_room(inv(), loc, focus):
		box.add_child(UIKit.label("点地上的箱子或者设备，走过去看。", 14, UIKit.MUTED))
		return
	var eid := inv().equipment_at(loc, focus)
	if eid != "":
		var slots := inv().equipment_slots(eid)
		if slots.is_empty():
			var def: Dictionary = DataDB.equipment().get(inv().equipment[eid]["def_id"], {})
			box.add_child(UIKit.label("%s：客人在这儿问价、付钱，你平时站在它后面。" % def.get("name", ""), 14, UIKit.MUTED))
		for sl in slots:
			box.add_child(view_for(sl, ShopSession.slot_name(inv(), sl), highlight))
		return
	if RoomGrid.is_aisle(inv(), loc, focus):
		box.add_child(UIKit.label("这格是过道（门口 / 收银台后面），不能堆东西。", 14, UIKit.MUTED))
		return
	box.add_child(view_for(inv().floor_slot(loc, focus), "地上（最多摞 %d 箱）" % (Inventory.FLOOR_CAPACITY / Package.UNITS["box"]), highlight))


## 手上和手推车。
func carry(box: HBoxContainer) -> void:
	UIKit.clear(box)
	var h := inv().hand()
	if not h.packages.is_empty():
		box.add_child(view_for(h, "手上（1 箱 / 3 包）"))
	else:
		box.add_child(view_for(h, "手上（%d 份）" % Inventory.HAND_MAX))
	var c := cart()
	if c != null:
		var pv := PackageView.new().setup(c, "手推车（2 箱）")
		pv.package_pressed.connect(_cart_menu)
		pv.slot_pressed.connect(_cart_slot)
		box.add_child(pv)


func _cart_menu(slot_id: String, at: Vector2) -> void:
	if walk_to_cart():
		package_menu(slot_id, at)


func _cart_slot(slot_id: String) -> void:
	if walk_to_cart():
		host._on_slot(slot_id)


## 一个货位用哪种面板：放着箱包、或者只能放箱包的用 PackageView，放散货的用 StackView（03）。
func view_for(sl: Slot, title: String, highlight := "") -> Control:
	var loose := sl.stack.height() > 0 or not sl.stack.collapsed_pile.is_empty()
	if not sl.packages.is_empty() or (sl.pkg_capacity > 0 and not loose and sl.type != "Hand"):
		var pv := PackageView.new().setup(sl, title)
		pv.package_pressed.connect(package_menu)
		pv.slot_pressed.connect(func(id): host._on_slot(id))
		return pv
	var v := StackView.new().setup(sl, title)
	v.highlight_item_id = highlight
	for pair in [["top_pressed", "_on_top"], ["strip_pressed", "_on_strip"], ["strip_peek", "_on_peek"], ["pile_pressed", "_on_pile"]]:
		if host.has_method(pair[1]):
			v.connect(pair[0], Callable(host, pair[1]))
	v.slot_pressed.connect(func(id): host._on_slot(id))
	return v


# ---------- 箱包菜单 ----------
## 点最上面那个箱 / 包时能做的事：[[文字, Callable], ...]。
func menu_items(slot_id: String) -> Array:
	var sl: Slot = inv().slots.get(slot_id)
	if sl == null or sl.packages.is_empty():
		return []
	var p: Package = sl.packages[-1]
	var h := inv().hand()
	var in_hand := slot_id == h.id
	var out: Array = []
	if not in_hand:
		out.append(["抱起来" if p.is_box() else "拿起来", func(): take(slot_id)])
	if p.is_box():
		if p.sealed:
			out.append(["拆箱（%d 秒）" % int(ActionAPI.OPEN_BOX_SECONDS), func(): open_box(slot_id)])
		else:
			out.append(["看看箱里", func(): look_into_box(slot_id)])
			if not in_hand and not p.packs.is_empty():
				out.append(["从箱里拿一包", func(): pack_from_box(slot_id)])
			if not in_hand and not h.packages.is_empty() and not h.packages[-1].is_box():
				out.append(["把手上的包放回箱里", func(): pack_into_box(slot_id)])
	else:
		out.append(["隔着袋子看一眼", func(): look_at_pack(slot_id)])
		if p.sealed:
			out.append(["撕开袋子", func(): open_pack(slot_id)])
		elif not in_hand:
			out.append(["拿一条到手上", func(): item_from_pack(slot_id)])
	out.append(["写标签…", func(): label_dialog(p)])
	return out


func package_menu(slot_id: String, at: Vector2) -> void:
	var items := menu_items(slot_id)
	if items.is_empty():
		return
	var menu := PopupMenu.new()
	for i in items.size():
		menu.add_item(items[i][0], i)
	menu.id_pressed.connect(func(id):
		items[id][1].call()
		refresh.call())
	menu.popup_hide.connect(menu.queue_free)
	host.add_child(menu)
	menu.position = Vector2i(at)
	menu.popup()


func take(slot_id: String) -> void:
	var r := api.take_package(slot_id)
	if not r["ok"]:
		say.call(r["reason"] + "。")
		return
	spend.call(ActionAPI.MOVE_PACKAGE_SECONDS)


func open_box(slot_id: String) -> void:
	if not api.open_box(slot_id):
		return
	spend.call(ActionAPI.OPEN_BOX_SECONDS)
	var box: Package = inv().slots[slot_id].packages[-1]
	say.call("划开胶带，箱子拆开了。里面 %d 包。" % box.packs.size())


## 掀开盖看一圈：每包的货号贴纸，数一数各几包。
func look_into_box(slot_id: String) -> void:
	var box: Package = inv().slots[slot_id].packages[-1]
	spend.call(ActionAPI.LOOK_INTO_BOX_SECONDS)
	if box.packs.is_empty():
		say.call("箱子空了。")
		return
	var counts := {}
	for pk in box.packs:
		var key := PackageView._sticker_text(pk)
		counts[key] = int(counts.get(key, 0)) + 1
	var parts: Array = []
	for key in counts:
		parts.append("%s ×%d" % [key, counts[key]])
	say.call("箱里 %d 包（贴纸）：%s。" % [box.packs.size(), "，".join(parts)])


func pack_from_box(slot_id: String) -> void:
	var r := api.take_pack_from_box(slot_id)
	if not r["ok"]:
		say.call(r["reason"] + "。")
		return
	spend.call(ActionAPI.MOVE_PACKAGE_SECONDS * 0.5)


func pack_into_box(slot_id: String) -> void:
	var r := api.put_pack_into_box(slot_id)
	if not r["ok"]:
		say.call(r["reason"] + "。")
		return
	spend.call(ActionAPI.MOVE_PACKAGE_SECONDS * 0.5)


func look_at_pack(slot_id: String) -> void:
	var p: Package = inv().slots[slot_id].packages[-1]
	var seen := api.look_at_pack(p)
	spend.call(1.0)
	if seen.is_empty():
		say.call("包是空的。")
		return
	say.call("隔着袋子看：最上面那条像是%s%s。" % [UIKit.sku_name(seen["sku_guess"]), "（图案款，可能看错）" if seen.get("may_be_wrong", false) else ""])


func open_pack(slot_id: String) -> void:
	if api.open_pack(slot_id):
		spend.call(ActionAPI.OPEN_PACK_SECONDS)


func item_from_pack(slot_id: String) -> void:
	if inv().hand().stack.is_full():
		say.call("手上拿不下了。")
		return
	if not inv().hand().packages.is_empty():
		say.call("手上抱着箱包，先放下。")
		return
	if api.take_from_open_pack(slot_id) != null:
		spend.call(ActionAPI.TAKE_TOP_SECONDS)


func label_dialog(p: Package) -> void:
	var d := AcceptDialog.new()
	d.title = "写标签"
	d.ok_button_text = "写上"
	var edit := LineEdit.new()
	edit.text = s.knowledge.labels.get(p.id, "")
	edit.placeholder_text = "比如：红格子羊毛 / 留着冬天卖（写空 = 擦掉）"
	edit.custom_minimum_size = Vector2(320, 0)
	d.add_child(edit)
	d.confirmed.connect(func():
		write_label(p.id, edit.text)
		refresh.call())
	d.close_requested.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	host.add_child(d)
	d.popup_centered()
	edit.grab_focus()


func write_label(pkg_id: String, text: String) -> void:
	api.write_label(pkg_id, text)
	spend.call(ActionAPI.LABEL_SECONDS)


## 点某格空处、手上抱着箱包时：能放就放上去；手上是包、那格放散货，就撕开倒上去（07 §2）。
## 手上没抱箱包返回 false（交给场景按散货处理）。
func put_from_hand(slot_id: String) -> bool:
	var h := inv().hand()
	if h.packages.is_empty() or slot_id == h.id:
		return false
	var sl: Slot = inv().slots[slot_id]
	var p: Package = h.packages[-1]
	var top_box_open := not sl.packages.is_empty() and sl.packages[-1].is_box() and not sl.packages[-1].sealed
	if sl.can_hold(p) or (sl.type == "Floor" and p.is_box()):
		var r := api.put_package(slot_id)
		if r["ok"]:
			spend.call(ActionAPI.MOVE_PACKAGE_SECONDS)
		else:
			say.call(r["reason"] + "。")
	elif not p.is_box() and top_box_open:
		pack_into_box(slot_id)
	elif not p.is_box() and sl.stack.max_height > 0 and sl.packages.is_empty():
		var was_sealed := p.sealed
		var r := api.unpack_to(h.id, slot_id)
		if r["ok"]:
			spend.call((ActionAPI.OPEN_PACK_SECONDS if was_sealed else 0.0) + int(r["moved"]) * ActionAPI.UNPACK_PER_ITEM_SECONDS)
			say.call("撕开袋子倒了 %d 条上去%s。" % [r["moved"], "，包里还剩 %d 条" % r["left"] if int(r["left"]) > 0 else "，包倒空了"])
		else:
			say.call(r["reason"] + "。")
	elif p.is_box() and sl.stack.max_height > 0:
		say.call("整箱放不上去。先拆箱，拿一包出来再倒上去。")
	else:
		say.call(api.put_package(slot_id)["reason"] + "。")
	return true


# ---------- 摆设备（时间不走） ----------
func set_layout(on: bool) -> void:
	layout_mode = on
	placing_def = ""
	picked_eid = ""
	view.placing_def = ""
	view.placing_ignore = ""
	view.selected_cell = focus if not on else Vector2i(-1, -1)


## 这间屋能摆的设备（按 def 的 room）。
func placeable_defs() -> Array:
	var room_type: String = inv().locations.get(loc, {}).get("type", "")
	var out: Array = []
	var defs := DataDB.equipment()
	for id in defs:
		var d = defs[id]
		if typeof(d) == TYPE_DICTIONARY and d.get("room", "") == room_type and not d.get("fixed", false):
			out.append(id)
	return out


func layout_panel(box: VBoxContainer, done: Callable) -> void:
	UIKit.clear(box)
	box.add_child(UIKit.label("摆设备（时间不走）：选一种点格子摆下；点已经摆好的设备可以挪或卖。", 13, UIKit.MUTED))
	var row := HFlowContainer.new()
	box.add_child(row)
	for id in placeable_defs():
		var d: Dictionary = DataDB.equipment()[id]
		var b := UIKit.button("%s %d 元" % [d["name"], int(s.equipment_price(id))], start_placing.bind(id), 14)
		b.toggle_mode = true
		b.button_pressed = placing_def == id and picked_eid == ""
		row.add_child(b)
	if picked_eid != "" and inv().equipment.has(picked_eid):
		var e: Dictionary = inv().equipment[picked_eid]
		var d: Dictionary = DataDB.equipment().get(e["def_id"], {})
		var prow := UIKit.hbox(6)
		prow.add_child(UIKit.label("选中：%s" % d.get("name", ""), 14, UIKit.ACCENT))
		prow.add_child(UIKit.button("挪到别处", start_moving, 14))
		prow.add_child(UIKit.button("卖掉（退 %d 元）" % roundi(s.equipment_price(e["def_id"]) * float(d.get("resale_ratio", 0))), sell_picked, 14))
		box.add_child(prow)
	var brow := UIKit.hbox(6)
	if placing_def != "":
		brow.add_child(UIKit.button("不摆了", cancel_placing, 14))
	brow.add_child(UIKit.button("摆好了", done, 14))
	box.add_child(brow)


func start_placing(def_id: String) -> void:
	placing_def = def_id
	picked_eid = ""
	view.placing_def = def_id
	view.placing_ignore = ""
	say.call("点一格把%s摆下去（绿框能摆，红框不行）。" % DataDB.equipment()[def_id]["name"])
	refresh.call()


func start_moving() -> void:
	placing_def = inv().equipment[picked_eid]["def_id"]
	view.placing_def = placing_def
	view.placing_ignore = picked_eid
	say.call("点一格，把它挪过去。")
	refresh.call()


func sell_picked() -> void:
	var r := api.sell_equipment(picked_eid)
	say.call("卖掉了，退回 %d 元。" % roundi(r["refund"]) if r["ok"] else r["reason"] + "。")
	if r["ok"]:
		picked_eid = ""
		view.selected_cell = Vector2i(-1, -1)
	check_reach()
	refresh.call()


func cancel_placing() -> void:
	placing_def = ""
	picked_eid = ""
	view.placing_def = ""
	view.placing_ignore = ""
	refresh.call()


func layout_click(c: Vector2i) -> void:
	if placing_def != "" and picked_eid != "" and view.placing_ignore == picked_eid:
		var r := api.move_equipment(picked_eid, c)
		say.call("挪好了。" if r["ok"] else r["reason"] + "。")
		if r["ok"]:
			placing_def = ""
			view.placing_def = ""
			view.placing_ignore = ""
	elif placing_def != "":
		var r := api.buy_equipment(placing_def, loc, c)
		if r["ok"]:
			say.call("摆好了%s，花了 %d 元。" % [DataDB.equipment()[placing_def]["name"], int(s.equipment_price(placing_def))])
		else:
			say.call(r["reason"] + "。")
	else:
		picked_eid = inv().equipment_at(loc, c)
		view.selected_cell = c if picked_eid != "" else Vector2i(-1, -1)
	check_reach()


## 门口走不到的设备标红，客人看不到上面的货（07 §4.1）。
func check_reach() -> void:
	var names: Array = []
	for eid in RoomGrid.unreachable(inv(), loc):
		names.append(DataDB.equipment().get(inv().equipment[eid]["def_id"], {}).get("name", "?"))
	if not names.is_empty():
		say.call("[color=#e05a4f]从门口走不到：%s。走不到的设备客人看不到，你也拿不到。[/color]" % "、".join(names))


func blocked_marks() -> Array:
	var out: Array = []
	for eid in RoomGrid.unreachable(inv(), loc):
		var pos: Array = inv().equipment[eid]["pos"]
		out.append({"cell": Vector2i(int(pos[0]), int(pos[1])), "color": UIKit.BAD})
	return out
