class_name RoomView
extends Control
## 店面、仓库的全景（07 §3、§4）：开罗式斜 45° 的一间屋子，后面两堵墙，前面临街敞开。
## 画地面格、设备（货架、货柜、橱窗、模特、收银台、仓库货架）、地堆的箱子和包、玩家与客人。
## 设备、纸箱、整包、手推车用美术线程的像素图；设备正面看得到每格货露出的边缘颜色（和近景面板一致），箱子只看得到纸箱。
## 点设备或地面 → cell_clicked；纯表现，规则都在核心层。

signal cell_clicked(cell: Vector2i)

const WALL_H := 96.0
## 临街那一侧多画几排街面（店面）
const STREET_ROWS := 2.0
const WALL_L := Color("#565c78")
const WALL_R := Color("#4a4f68")
const CARDBOARD := Color("#b08a5a")
## 纸箱、整包的精灵高度（美术像素，assets/sprites/equipment.json）
const BOX_ART_H := 8.0
const BAG_ART_H := 3.0

var inv: Inventory
var loc: String = ""
var show_street := false
## 屋里的地面贴图（Iso.draw_ground 的 kind）：店面木地板 wood（以后装修可换 tile），仓库水泥地 concrete
var floor_kind := "wood"
## 玩家站的位置（格坐标，可以是小数，走路时插值）
var player_g := Vector2(0, 0)
var _player_path: Array[Vector2] = []
var _player_dir := Vector2(1, 0)
var _player_phase := 0.0
## 手推车停在哪（格坐标的脚下点）；x < -50 表示不画
var cart_g := Vector2(-99, -99)
var cart_slot: Slot
## 高亮的格子：{cell: Vector2i, color: Color}（客人要的货在哪、走不到的设备）
var marks: Array = []
var hover_cell := Vector2i(-1, -1)
var selected_cell := Vector2i(-1, -1)
## 摆设备时要预览的设备 def_id（空 = 不在摆放）
var placing_def := ""
var placing_ok := false
## 挪设备时它自己那格不算占着
var placing_ignore := ""


func setup(inventory: Inventory, location_id: String) -> RoomView:
	inv = inventory
	loc = location_id
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func room() -> Vector2i:
	return inv.room_size(loc)


func _fit() -> Dictionary:
	var sz := room()
	var rows := float(sz.y) + (STREET_ROWS if show_street else 0.3)
	var n := float(sz.x) + rows
	var w := n * Iso.TW * 0.5
	var h := n * Iso.TH * 0.5 + WALL_H + 10.0
	# 像素风：缩放只取 0.5 的整数倍，原点对齐像素网格（docs/08）
	var k := maxf(0.5, floorf(minf(1.5, minf(size.x / w, size.y / h)) * 2.0) / 2.0)
	var left := Iso.to_screen(Vector2(0, rows), Vector2.ZERO).x
	var origin := Iso.snap(Vector2((size.x / k - w) * 0.5 - left, (size.y / k - h) * 0.5 + WALL_H + 4.0))
	return {"origin": origin, "k": k}


func cell_at(p: Vector2) -> Vector2i:
	var f := _fit()
	var q: Vector2 = p / float(f["k"]) - f["origin"]
	var a := q.x / (Iso.TW * 0.5)
	var b := q.y / (Iso.TH * 0.5)
	return Vector2i(floori((a + b) * 0.5), floori((b - a) * 0.5))


func screen_of(g: Vector2) -> Vector2:
	var f := _fit()
	return Iso.to_screen(g, f["origin"]) * float(f["k"])


## 设备 / 地堆在屏幕上的外框（点它们的正面也算点到那格）。
func _object_rect(c: Vector2i, height: float) -> Rect2:
	var f := _fit()
	var o: Vector2 = f["origin"]
	var k: float = f["k"]
	var g := Vector2(c)
	var pts := [Iso.to_screen(g + Vector2(0, 1), o), Iso.to_screen(g + Vector2(1, 1), o), Iso.to_screen(g + Vector2(1, 0), o),
		Iso.to_screen(g, o) - Vector2(0, height)]
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return Rect2(r.position * k, r.size * k)


## 每格上立着的东西有多高（像素，未缩放），点击时按它的正面判定。
func _height_at(c: Vector2i) -> float:
	var eid := inv.equipment_at(loc, c)
	if eid != "":
		return _equip_height(inv.equipment[eid]["def_id"])
	for sl in inv.slots_in(loc, "Floor"):
		if sl.grid_pos == c:
			return _pile_height(sl)
	return 0.0


func _equip_height(def_id: String) -> float:
	var h := Iso.equipment_height(def_id)
	return h if h > 0.0 else 40.0


func _pile_height(sl: Slot) -> float:
	var h := 0.0
	for p in sl.packages:
		h += (BOX_ART_H if p.is_box() else BAG_ART_H) * Iso.PX
	return h


func pick_cell(p: Vector2) -> Vector2i:
	# 先看前面那些高的东西有没有被点到（越靠前越先），都没有再按地面算
	var best := Vector2i(-1, -1)
	var best_depth := -INF
	var sz := room()
	for x in sz.x:
		for y in sz.y:
			var c := Vector2i(x, y)
			var h := _height_at(c)
			if h <= 0.0:
				continue
			if _object_rect(c, h).has_point(p) and x + y > best_depth:
				best_depth = x + y
				best = c
	if best.x >= 0:
		return best
	return cell_at(p)


func _gui_input(e: InputEvent) -> void:
	if inv == null:
		return
	if e is InputEventMouseMotion:
		var c := cell_at(e.position) if placing_def != "" else pick_cell(e.position)
		if c != hover_cell:
			hover_cell = c
			if placing_def != "":
				placing_ok = RoomGrid.can_place(inv, loc, placing_def, c, placing_ignore) == ""
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(e.position) if placing_def != "" else pick_cell(e.position)
		if RoomGrid.in_room(inv, loc, c):
			cell_clicked.emit(c)
			accept_event()


## 玩家直接站到某格（进场、换场景时）。
func place_player(c: Vector2i) -> void:
	player_g = Vector2(c)
	_player_path.clear()
	if c == inv.room_cell(loc, "stand"):
		_player_dir = Vector2(0, 1)


## 沿着 RoomGrid.path 给的格子一格格走过去（只是动画，时间由场景按步数另算）。
func follow_path(cells: Array[Vector2i]) -> void:
	_player_path.clear()
	for c in cells:
		_player_path.append(Vector2(c))


func player_walking() -> bool:
	return not _player_path.is_empty()


func step(dt: float) -> void:
	var left := dt * 4.0
	while left > 0.0 and not _player_path.is_empty():
		var to := _player_path[0] - player_g
		if to.length() <= left:
			player_g = _player_path.pop_front()
			left -= to.length()
		else:
			player_g += to.normalized() * left
			left = 0.0
		if to.length() > 0.001:
			_player_dir = to
		if _player_path.is_empty() and Vector2i(player_g.round()) == inv.room_cell(loc, "stand"):
			# 回到收银台后面：转过身朝着店里
			_player_dir = Vector2(0, 1)
	_player_phase = _player_phase + dt if not _player_path.is_empty() else 0.0
	queue_redraw()


# ---------- 绘制 ----------
func _draw() -> void:
	if inv == null:
		return
	var f := _fit()
	var k: float = f["k"]
	var o: Vector2 = f["origin"]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var sz := room()
	if show_street:
		# 门外：一排人行道，再外面是街
		for x in range(-1, sz.x + 1):
			for r in int(STREET_ROWS):
				Iso.draw_ground(self, o, Vector2(x, sz.y + r), "pavement" if r == 0 else "road", x * 7 + r * 13, "se" if r == 0 else "")
	for x in sz.x:
		for y in sz.y:
			Iso.draw_ground(self, o, Vector2(x, y), floor_kind, x * 5 + y * 11)
	_draw_walls(o, sz)
	_draw_marks(o)
	_draw_ground_frames(o)
	# 立着的东西按远近排序后画
	var things: Array = []
	for eid in inv.equipment_in(loc):
		var e: Dictionary = inv.equipment[eid]
		if e.has("pos"):
			things.append({"d": float(e["pos"][0]) + float(e["pos"][1]) + 1.0, "kind": "equip", "eid": eid})
	for sl in inv.slots_in(loc, "Floor"):
		if not sl.packages.is_empty():
			things.append({"d": float(sl.grid_pos.x + sl.grid_pos.y) + 1.0, "kind": "pile", "slot": sl})
	if cart_g.x > -50.0:
		things.append({"d": cart_g.x + cart_g.y, "kind": "cart"})
	_collect_people(things)
	things.sort_custom(_draw_before)
	for t in things:
		match t["kind"]:
			"equip":
				_draw_equipment(o, t["eid"])
			"pile":
				_draw_pile(o, t["slot"])
			"person":
				_draw_person_thing(o, t)
			"cart":
				_draw_cart(o)
	_draw_overlay(o)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 画家算法的先后：远的先画。远近一样时人在后画：人站在设备 / 箱堆斜对角那格（左前或右前）时，
## 他挡着的正好是设备朝外的那一面，应该画在设备前面；排序不稳定的话会时前时后。
static func _draw_before(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["d"]), float(b["d"])):
		return float(a["d"]) < float(b["d"])
	return a["kind"] != "person" and b["kind"] == "person"


func _draw_walls(o: Vector2, sz: Vector2i) -> void:
	var up := Vector2(0, -WALL_H)
	var a := Iso.to_screen(Vector2(0, 0), o)
	var b := Iso.to_screen(Vector2(sz.x, 0), o)
	var c := Iso.to_screen(Vector2(0, sz.y), o)
	draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), WALL_R)
	draw_colored_polygon(PackedVector2Array([c, a, a + up, c + up]), WALL_L)
	draw_line(a, a + up, Iso.OUTLINE, 1.0)
	draw_line(a + up, b + up, Iso.OUTLINE, 1.0)
	draw_line(a + up, c + up, Iso.OUTLINE, 1.0)
	# 墙脚线
	draw_line(a, b, Color(0, 0, 0, 0.25), 2.0)
	draw_line(a, c, Color(0, 0, 0, 0.25), 2.0)


## 地面上的标记：门口、卸货区、收银台后你站的地方。
func _draw_marks(o: Vector2) -> void:
	var L: Dictionary = inv.locations.get(loc, {})
	for u in L.get("unload", []):
		Iso.draw_tile(self, o, Vector2(float(u[0]), float(u[1])), Color(0.95, 0.75, 0.2, 0.18), 1.0, 1.0, Color(0.95, 0.75, 0.2, 0.6))
	if L.has("door"):
		var d := Vector2(float(L["door"][0]), float(L["door"][1]))
		Iso.draw_tile(self, o, d + Vector2(0.1, 0.55), Color("#7a3a32"), 0.8, 0.4, Color(0, 0, 0, 0))
		draw_string(get_theme_default_font(), Iso.to_screen(d + Vector2(0.5, 1.0), o) + Vector2(-8, 14), "门", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)


func _pulse() -> float:
	return 0.55 + 0.45 * sin(Time.get_ticks_msec() / 160.0)


## 高亮、选中、悬停的菱形框画在地面层（设备和人之前），不会切过货架正面；立着的东西另外整体提亮 / 染色（_cell_tint）。
func _draw_ground_frames(o: Vector2) -> void:
	var pulse := _pulse()
	for m in marks:
		var pts := Iso.tile_points(Vector2(m["cell"]), o)
		pts.append(pts[0])
		draw_polyline(pts, Color(m["color"], pulse), 2.5)
	if RoomGrid.in_room(inv, loc, selected_cell):
		var pts := Iso.tile_points(Vector2(selected_cell), o)
		pts.append(pts[0])
		draw_polyline(pts, UIKit.ACCENT, 2.0)
	if RoomGrid.in_room(inv, loc, hover_cell):
		var col := Color(1, 1, 1, 0.6)
		if placing_def != "":
			col = UIKit.GOOD if placing_ok else UIKit.BAD
		var pts := Iso.tile_points(Vector2(hover_cell), o)
		pts.append(pts[0])
		draw_polyline(pts, col, 1.5)


## 立在这格上的设备 / 箱堆画的时候乘的颜色：要的货在这（金框）、走不到（红框）往那个颜色染，选中、悬停时提亮。
func _cell_tint(c: Vector2i) -> Color:
	var col := Color.WHITE
	for m in marks:
		if m["cell"] == c:
			col = col.lerp(m["color"], 0.35 * _pulse())
	if c == selected_cell:
		col *= 1.15
	elif c == hover_cell and placing_def == "":
		col *= 1.08
	col.a = 1.0
	return col


## 摆设备时的预览：半透明的方块（绿能摆，红不行），画在最上面。
func _draw_overlay(o: Vector2) -> void:
	if placing_def != "" and RoomGrid.in_room(inv, loc, hover_cell):
		var col := UIKit.GOOD if placing_ok else UIKit.BAD
		Iso.draw_box(self, o, Vector2(hover_cell) + Vector2(0.1, 0.1), 0.8, 0.8, _equip_height(placing_def), Color(col, 0.35), Color(col, 0.45))


func _facing(c: Vector2i) -> String:
	return RoomGrid.facing(inv, loc, c)


## 设备用美术线程的像素图（docs/08 §5）：货架、橱窗每层按货堆从下往上画叠好的围巾（看得到的边缘色），
## 模特披着最上面那条，仓库货架每层画箱和包。
func _draw_equipment(o: Vector2, eid: String) -> void:
	var e: Dictionary = inv.equipment[eid]
	var c := Vector2i(int(e["pos"][0]), int(e["pos"][1]))
	var def_id: String = e["def_id"]
	var slots := inv.equipment_slots(eid)
	var extra := {}
	match def_id:
		"shop_shelf", "shop_window":
			var tiers: Array = []
			for sl in slots:
				tiers.append(sl.stack.items.map(func(it): return UIKit.sku_color(it.sku_id)))
			extra["tiers"] = tiers
		"mannequin":
			if not slots.is_empty() and slots[0].stack.height() > 0:
				extra["scarf"] = UIKit.sku_color(slots[0].stack.items[-1].sku_id)
		"warehouse_rack":
			var boxes: Array = []
			var bags: Array = []
			for sl in slots:
				boxes.append(sl.packages.filter(func(p): return p.is_box()).size())
				bags.append(sl.packages.filter(func(p): return not p.is_box()).size())
			extra["boxes"] = boxes
			extra["bags"] = bags
	extra["col"] = _cell_tint(c)
	Iso.draw_equipment(self, o, Vector2(c), def_id, _facing(c), extra)
	# 抽塌了掉在设备前面地上的货
	for sl in slots:
		if not sl.stack.collapsed_pile.is_empty():
			var foot := Iso.to_screen(Vector2(c) + Vector2(0.5, 1.15), o)
			for m in mini(sl.stack.collapsed_pile.size(), 5):
				draw_rect(Rect2(foot + Vector2(-14 + m * 6, -3 - (m % 2) * 2), Vector2(10, 4)), UIKit.sku_color(sl.stack.collapsed_pile[m].sku_id))


## 地堆：纸箱一箱箱摞起来，包是扁扁的一袋（隔着袋子透出最上面那条的颜色）。拆开的箱子颜色浅一点。
func _draw_pile(o: Vector2, sl: Slot) -> void:
	var g := Vector2(sl.grid_pos)
	var tint := _cell_tint(sl.grid_pos)
	var z := 0.0
	for p in sl.packages:
		if p.is_box():
			Iso.draw_sprite(self, o, g, "eq_carton", (Color.WHITE if p.sealed else Color(1.0, 0.93, 0.85)) * tint, z)
			z += BOX_ART_H
		else:
			var top := p.top_item()
			Iso.draw_sprite(self, o, g + Vector2(0.3, 0.3), "eq_bag", (Color.WHITE.lerp(UIKit.sku_color(top.sku_id), 0.45) if top else Color.WHITE) * tint, z)
			z += BAG_ART_H


## 手推车：车板上摞着车里的箱 / 包。
func _draw_cart(o: Vector2) -> void:
	var g := cart_g - Vector2(0.5, 0.5)
	Iso.draw_equipment(self, o, g, "handcart", "sw")
	if cart_slot == null:
		return
	var z := float(Iso.sprite_meta("eq_handcart_sw").get("H", 3))
	for p in cart_slot.packages:
		if p.is_box():
			Iso.draw_sprite(self, o, g + Vector2(0.25, 0.3), "eq_carton_small_sw", Color.WHITE if p.sealed else Color(1.0, 0.93, 0.85), z)
			z += float(Iso.sprite_meta("eq_carton_small_sw").get("H", 6))
		else:
			var top := p.top_item()
			Iso.draw_sprite(self, o, g + Vector2(0.35, 0.4), "eq_bag", Color.WHITE.lerp(UIKit.sku_color(top.sku_id), 0.45) if top else Color.WHITE, z)
			z += BAG_ART_H


# ---------- 人 ----------
## 子类往 things 里加人：{d, kind: "person", g（脚下点）, body, hair, facing, back, phase, tag}
func _collect_people(things: Array) -> void:
	var fb := Iso.facing_of(_player_dir)
	var foot := player_g + Vector2(0.5, 0.5)
	things.append({"d": foot.x + foot.y, "kind": "person", "g": foot, "body": UIKit.ACCENT, "hair": Color("#2a2026"),
		"style": Iso.Hair.SHORT, "pants": Color("#3a3a4a"), "facing": fb[0], "back": fb[1], "phase": _player_phase,
		"tag": "你", "carry": _hand_carry()})


## 手上抱着什么（画在小人身前）：箱子、包或散货的颜色。
func _hand_carry() -> Dictionary:
	var h := inv.hand()
	if not h.packages.is_empty():
		var p: Package = h.packages[-1]
		var top := p.top_item()
		return {"box": p.is_box(), "n": h.packages.size(), "color": CARDBOARD if p.is_box() else (UIKit.sku_color(top.sku_id) if top else Color.WHITE)}
	if h.stack.height() > 0:
		return {"box": false, "n": h.stack.height(), "color": UIKit.sku_color(h.stack.items[-1].sku_id)}
	return {}


func _draw_person_thing(o: Vector2, t: Dictionary) -> void:
	var foot := Iso.to_screen(t["g"], o)
	Iso.draw_person(self, foot, t["body"], t["hair"], t["facing"], t["phase"], t["back"], 1.0,
		t.get("style", -1), t.get("pants", Color(0, 0, 0, 0)), t.get("scarf", Color(0, 0, 0, 0)))
	var c: Dictionary = t.get("carry", {})
	if not c.is_empty():
		var at := foot + Vector2(-9, -34)
		if c["box"]:
			draw_rect(Rect2(at + Vector2(-2, -6), Vector2(22, 16)), c["color"])
			draw_rect(Rect2(at + Vector2(-2, -6), Vector2(22, 16)), Iso.OUTLINE, false, 1.0)
		else:
			for i in mini(int(c["n"]), 3):
				draw_rect(Rect2(at + Vector2(0, 4 - i * 5), Vector2(18, 4)), c["color"].lerp(Color.WHITE, 0.2 * i))
	if t.get("tag", "") != "":
		draw_string(get_theme_default_font(), foot + Vector2(-30, 16), t["tag"], HORIZONTAL_ALIGNMENT_CENTER, 60, 12, t.get("tag_color", UIKit.TEXT))
