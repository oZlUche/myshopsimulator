class_name RoomGrid
extends RefCounted
## 店面、仓库的地面格子（07 §3、§4）：哪些格能走、走到某件设备跟前要几步。
## 设备占的格子走不过去；门口、收银台后面这些保留格不能摆东西。

## 走一格要的时间（秒，1x）
const STEP_SECONDS := 0.6
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func in_room(inv: Inventory, loc: String, c: Vector2i) -> bool:
	var sz := inv.room_size(loc)
	return c.x >= 0 and c.y >= 0 and c.x < sz.x and c.y < sz.y


## 不能摆设备的格子：门口、卸货区、收银台后玩家站的位置。
static func reserved(inv: Inventory, loc: String, c: Vector2i) -> bool:
	var L: Dictionary = inv.locations.get(loc, {})
	for key in ["door", "stand"]:
		if L.has(key) and Vector2i(int(L[key][0]), int(L[key][1])) == c:
			return true
	for u in L.get("unload", []):
		if Vector2i(int(u[0]), int(u[1])) == c:
			return true
	return false


## 门口、收银台后面那格是过道：不能摆设备，也不能堆箱子。
static func is_aisle(inv: Inventory, loc: String, c: Vector2i) -> bool:
	var L: Dictionary = inv.locations.get(loc, {})
	for key in ["door", "stand"]:
		if L.has(key) and Vector2i(int(L[key][0]), int(L[key][1])) == c:
			return true
	return false


## 能走的格：在屋里、没摆设备、也不是地堆（箱子堆着的格子绕着走）。
static func walkable(inv: Inventory, loc: String, c: Vector2i) -> bool:
	if not in_room(inv, loc, c) or inv.equipment_at(loc, c) != "":
		return false
	for sl in inv.slots_in(loc, "Floor"):
		if sl.grid_pos == c and not sl.packages.is_empty():
			return false
	return true


## 从 from 走到 target 跟前（target 本身能走就走到上面，否则走到相邻的能走的格）要几步；到不了返回 -1。
static func steps_to(inv: Inventory, loc: String, from: Vector2i, target: Vector2i) -> int:
	if from == target:
		return 0
	var p := path(inv, loc, from, target, walkable(inv, loc, target))
	return p.size() - 1 if not p.is_empty() else -1


## 走过去的路线（含起点那格）：onto = 走到 target 上面，否则走到它旁边能走的那格。
## 已经在旁边（或就在上面）返回 [from]；走不到返回 []。
static func path(inv: Inventory, loc: String, from: Vector2i, target: Vector2i, onto := false) -> Array[Vector2i]:
	var parent := {from: from}
	var q: Array[Vector2i] = [from]
	var goal := Vector2i(-1, -1)
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		var d := (c - target).abs()
		if (onto and c == target) or (not onto and d.x + d.y == 1):
			goal = c
			break
		if not onto and c == target and c == from:
			goal = c
			break
		for dir in DIRS:
			var n: Vector2i = c + dir
			if parent.has(n) or not walkable(inv, loc, n):
				continue
			parent[n] = c
			q.append(n)
	if goal.x < 0:
		return []
	var out: Array[Vector2i] = [goal]
	while out[0] != from:
		out.push_front(parent[out[0]])
	return out


static func walk_seconds(inv: Inventory, loc: String, from: Vector2i, target: Vector2i) -> float:
	var n := steps_to(inv, loc, from, target)
	return STEP_SECONDS * maxi(n, 0)


## 能不能把 def_id 这种设备摆到 c：在屋里、不是保留格、格子空着、橱窗只能摆在临街那排、
## 摆上以后门口到每件设备跟前（以及收银台）都还走得通。
static func can_place(inv: Inventory, loc: String, def_id: String, c: Vector2i, ignore_eid := "") -> String:
	var def: Dictionary = DataDB.equipment().get(def_id, {})
	if not in_room(inv, loc, c):
		return "出界了"
	var room_type: String = inv.locations.get(loc, {}).get("type", "")
	if def.has("room") and def["room"] != room_type:
		return "这种设备不摆在这儿"
	if reserved(inv, loc, c):
		return "这格要留着走路"
	var occupant := inv.equipment_at(loc, c)
	if occupant != "" and occupant != ignore_eid:
		return "这格已经摆了东西"
	for sl in inv.slots_in(loc, "Floor"):
		if sl.grid_pos == c and not sl.packages.is_empty():
			return "地上堆着箱子"
	if def.get("front_only", false) and c.y != inv.room_size(loc).y - 1:
		return "橱窗只能摆在临街那排"
	return ""


## 门口到每件设备跟前都要走得通，否则这件设备等于没摆（07 §4.1）。返回走不到的设备 ID 列表。
static func unreachable(inv: Inventory, loc: String) -> Array:
	var door := inv.room_cell(loc, "door")
	var out: Array = []
	for eid in inv.equipment_in(loc):
		var e: Dictionary = inv.equipment[eid]
		if not e.has("pos"):
			continue
		if steps_to(inv, loc, door, Vector2i(int(e["pos"][0]), int(e["pos"][1]))) < 0:
			out.append(eid)
	return out
