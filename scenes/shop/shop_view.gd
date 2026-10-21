class_name ShopView
extends RoomView
## 店面全景（07 §4.2）：在 RoomView 上加客人和门口街上的行人。
## 客人从街上进门，走到展架旁边看货；问价、讲价、等货时到收银台前排队；走了就出门上街。
## 纯表现：客人的状态都在 ShopSession，这里只管走位和画。

## 点到了某位客人（问价的去讲价、等货的交货，由店面界面决定）
signal visitor_clicked(visitor: Dictionary)

const WALK_SPEED := 2.2
const COUNTER_STATES := ["asking", "haggling", "waiting_item"]

var session: StallSession
## 客人编号 → 显示用
var visitor_numbers: Dictionary = {}
## 客人 id → {g 脚下点, path 剩下的路, spot 目标格, look 站定后朝哪看, seed, v}
var _actors: Dictionary = {}
## 街上走过的人、离店的人：{g, vel, seed, path}
var _walkers: Array = []


func _init() -> void:
	show_street = true


## 门口路过一个人（没进店的就在街上走过去；进店的由 session.visitors 生成）。
func add_walker(stayed: bool) -> void:
	if stayed:
		return
	var from_left := randf() < 0.5
	var w := float(room().x)
	_walkers.append({"g": Vector2(-0.9 if from_left else w + 0.9, room().y + randf_range(1.1, STREET_ROWS - 0.2)),
		"vel": Vector2((1 if from_left else -1) * randf_range(1.2, 2.0), 0), "seed": randi() % 1000, "path": []})


func _door() -> Vector2i:
	return inv.room_cell(loc, "door")


func _foot(c: Vector2i, seed_value: int) -> Vector2:
	# 同一格站两个人时错开一点
	var j := Vector2(float(seed_value % 7 - 3), float((seed_value / 7) % 7 - 3)) * 0.04
	return Vector2(c) + Vector2(0.5, 0.5) + j


func _front_of(c: Vector2i) -> Vector2i:
	return RoomGrid.front(inv, loc, c)


## 收银台前排队的格子：先是收银台正前方那格，再从那里往外一圈圈排，不排到收银台后面（你站的那一侧）。
func _counter_queue() -> Array:
	var counter := inv.room_cell(loc, "counter")
	var stand := inv.room_cell(loc, "stand")
	var door := _door()
	var out: Array = []
	var front := _front_of(counter)
	var seen := {counter: true, stand: true, front: true}
	var q: Array = [front]
	if RoomGrid.walkable(inv, loc, front):
		out.append(front)
	while not q.is_empty() and out.size() < 8:
		var c: Vector2i = q.pop_front()
		for d in RoomGrid.DIRS:
			var n: Vector2i = c + d
			if seen.has(n) or not RoomGrid.walkable(inv, loc, n):
				continue
			seen[n] = true
			q.append(n)
			if n != door and n.y >= counter.y:
				out.append(n)
	return out


## 逛店时站的格子：展架、模特开口那一侧能站人的格；开口那侧站不了（比如橱窗朝街）才站旁边。
func _browse_cells() -> Array:
	var out: Array = []
	var stand := inv.room_cell(loc, "stand")
	for sl in session.display_slots():
		var e: Dictionary = inv.equipment.get(sl.equipment_id, {})
		if not e.has("pos"):
			continue
		var c := Vector2i(int(e["pos"][0]), int(e["pos"][1]))
		var front := _front_of(c)
		var cands: Array = [front]
		if not RoomGrid.walkable(inv, loc, front):
			cands = []
			for d in RoomGrid.DIRS:
				cands.append(c + d)
		for n in cands:
			if n != stand and n != _door() and RoomGrid.walkable(inv, loc, n) and not out.has(n):
				out.append(n)
	return out


## 每位客人此刻该站哪格。
func _spots() -> Dictionary:
	var out := {}
	var queue := _counter_queue()
	var qi := 0
	for v in session.visitors:
		if v["state"] in COUNTER_STATES and not queue.is_empty():
			out[v["customer"].id] = queue[mini(qi, queue.size() - 1)]
			qi += 1
	var browse := _browse_cells()
	var taken := {}
	for v in session.visitors:
		var id: String = v["customer"].id
		if out.has(id):
			continue
		if browse.is_empty():
			out[id] = _door()
			continue
		var start := absi(hash(id)) % browse.size()
		var pick: Vector2i = browse[start]
		for k in browse.size():
			var c: Vector2i = browse[(start + k) % browse.size()]
			if not taken.has(c):
				pick = c
				break
		taken[pick] = true
		out[id] = pick
	return out


func _route(from: Vector2, to: Vector2i, seed_value: int) -> Array:
	var cell := Vector2i(floori(from.x), floori(from.y))
	var out: Array = []
	if not RoomGrid.in_room(inv, loc, cell):
		# 从街上先走到门口
		out.append(_foot(_door(), seed_value) + Vector2(0, 0.6))
		cell = _door()
	var p := RoomGrid.path(inv, loc, cell, to, true)
	if p.is_empty():
		out.append(_foot(to, seed_value))
		return out
	for c in p:
		out.append(_foot(c, seed_value))
	return out


func step(dt: float) -> void:
	super.step(dt)
	if session == null:
		return
	var spots := _spots()
	var alive := {}
	for v in session.visitors:
		var id: String = v["customer"].id
		alive[id] = true
		var spot: Vector2i = spots.get(id, _door())
		if not _actors.has(id):
			var seed_value := absi(hash(id))
			var start := _foot(_door(), seed_value) + Vector2(0, 1.6)
			_actors[id] = {"g": start, "path": [], "spot": Vector2i(-9, -9), "look": Vector2(0, -1), "seed": seed_value, "v": v}
		var a: Dictionary = _actors[id]
		a["v"] = v
		if a["spot"] != spot:
			a["spot"] = spot
			a["path"] = _route(a["g"], spot, a["seed"])
			a["look"] = _look_dir(spot, v)
		_move(a, dt)
	# 走掉的客人：出门上街，混进行人里走远
	for id in _actors.keys():
		if alive.has(id):
			continue
		var a: Dictionary = _actors[id]
		var path: Array = []
		var cell := Vector2i(floori(a["g"].x), floori(a["g"].y))
		if RoomGrid.in_room(inv, loc, cell):
			for c in RoomGrid.path(inv, loc, cell, _door(), true):
				path.append(_foot(c, a["seed"]))
		path.append(_foot(_door(), a["seed"]) + Vector2(0, 1.4))
		var right: bool = int(a["seed"]) % 2 == 0
		_walkers.append({"g": a["g"], "vel": Vector2(1.6 if right else -1.6, 0), "seed": a["seed"], "path": path})
		_actors.erase(id)
	for w in _walkers:
		if not w["path"].is_empty():
			_move(w, dt)
		else:
			w["g"] += w["vel"] * dt
	var limit := float(room().x) + 1.0
	_walkers = _walkers.filter(func(w): return w["g"].x > -1.0 and w["g"].x < limit)


func _move(a: Dictionary, dt: float) -> void:
	var left := dt * WALK_SPEED
	a["moving"] = false
	while left > 0.0 and not a["path"].is_empty():
		var to: Vector2 = a["path"][0] - a["g"]
		if to.length() > 0.001:
			a["dir"] = to
			a["moving"] = true
		if to.length() <= left:
			a["g"] = a["path"].pop_front()
			left -= to.length()
		else:
			a["g"] += to.normalized() * left
			left = 0.0


## 站定以后朝哪看：排队的看收银台，逛的看开口朝着他的那个货架（没有就看旁边随便哪个）。
func _look_dir(spot: Vector2i, v: Dictionary) -> Vector2:
	if v["state"] in COUNTER_STATES:
		return Vector2(inv.room_cell(loc, "counter") - spot)
	for d in RoomGrid.DIRS:
		if inv.equipment_at(loc, spot + d) != "" and _front_of(spot + d) == spot:
			return Vector2(d)
	for d in RoomGrid.DIRS:
		var eid := inv.equipment_at(loc, spot + d)
		if eid != "":
			return Vector2(d)
	return Vector2(0, -1)


func _actor_rect(a: Dictionary) -> Rect2:
	var f := _fit()
	var k: float = f["k"]
	var r := Iso.person_rect(Iso.to_screen(a["g"], f["origin"]))
	return Rect2(r.position * k, r.size * k)


func _gui_input(e: InputEvent) -> void:
	if session != null and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and placing_def == "":
		# 前面的人挡住后面的，从近到远找
		var order := _actors.values()
		order.sort_custom(func(a, b): return a["g"].x + a["g"].y > b["g"].x + b["g"].y)
		for a in order:
			if _actor_rect(a).has_point(e.position):
				visitor_clicked.emit(a["v"])
				accept_event()
				return
	super._gui_input(e)


func _collect_people(things: Array) -> void:
	super._collect_people(things)
	var t := Time.get_ticks_msec() / 1000.0
	var you := Vector2i(player_g.round())
	for id in _actors:
		var a: Dictionary = _actors[id]
		var fit := Iso.outfit_full(a["seed"])
		var fc := Iso.facing_of(a.get("dir", a["look"]) if a.get("moving", false) else a["look"])
		var v: Dictionary = a["v"]
		var col := {"browsing": Color("#b8b5c4"), "asking": UIKit.ACCENT, "haggling": Color("#6fa8dc"), "waiting_item": UIKit.GOOD}.get(v["state"], Color.GRAY) as Color
		var g: Vector2 = a["g"]
		# 你走到他站的那格拿货时，他往旁边让半步，别把你整个挡住
		if not a.get("moving", false) and Vector2i(g.floor()) == you:
			g += Vector2(-0.45, 0.25)
		things.append({"d": g.x + g.y, "kind": "person", "g": g, "body": fit["top"], "hair": fit["hair"],
			"style": fit["style"], "pants": fit["pants"], "scarf": fit["scarf"], "facing": fc[0], "back": fc[1],
			"phase": t + a["seed"] * 0.1 if a.get("moving", false) else 0.0,
			"tag": "#%d" % visitor_numbers.get(id, 0), "tag_color": col, "visitor": v})
	for w in _walkers:
		var fit := Iso.outfit_full(int(w["seed"]))
		var dir: Vector2 = w["vel"] if w["path"].is_empty() else w.get("dir", w["vel"])
		var fc := Iso.facing_of(dir)
		things.append({"d": w["g"].x + w["g"].y, "kind": "person", "g": w["g"], "body": fit["top"], "hair": fit["hair"],
			"style": fit["style"], "pants": fit["pants"], "scarf": fit["scarf"], "facing": fc[0], "back": fc[1],
			"phase": t + float(w["seed"]) * 0.1})


func _draw_person_thing(o: Vector2, t: Dictionary) -> void:
	super._draw_person_thing(o, t)
	var v: Dictionary = t.get("visitor", {})
	if v.is_empty():
		return
	var p := Iso.to_screen(t["g"], o)
	var bubble_at := p + Vector2(14, -76)
	match v["state"]:
		"asking":
			Iso.draw_bubble(self, bubble_at, "ask")
		"haggling":
			Iso.draw_bubble(self, bubble_at, "haggle")
		"waiting_item":
			Iso.draw_bubble(self, bubble_at, "wait")
			var left := clampf(float(v["wait"]) / maxf(session.wait_for_item(v["customer"]), 1.0), 0.0, 1.0)
			draw_rect(Rect2(p + Vector2(-12, 20), Vector2(24, 3)), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(p + Vector2(-12, 20), Vector2(24 * left, 3)), UIKit.GOOD if left > 0.3 else UIKit.BAD)
