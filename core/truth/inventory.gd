class_name Inventory
extends RefCounted
## 库存物理模型（01 §4.1）：场所、槽位、设备实例与全部围巾。所有模块的读写底座。

## {location_id: {id, type, area_m2, rent_per_m2, humidity}}
var locations: Dictionary = {}
## {slot_id: Slot}
var slots: Dictionary = {}
## {equipment_instance_id: {def_id, location_id, slot_ids, pos?: [gx, gy]}}
var equipment: Dictionary = {}
## 手的主人：手上能拿多少看他的【搬运】（02 §2.10）。GameState 负责连上，不存档；没连上按 0 级算。
var player: PlayerState
var _next_item := 1
var _next_slot := 1
var _next_equip := 1
var _next_pkg := 1


func new_item_id() -> String:
	var id := "it_%06d" % _next_item
	_next_item += 1
	return id


func create_item(sku_id: String, provenance: Dictionary = {}) -> ScarfItem:
	var it := ScarfItem.new(new_item_id(), sku_id)
	it.provenance = provenance
	return it


func add_location(id: String, type: String, area_m2: float = 0.0) -> void:
	locations[id] = {"id": id, "type": type, "area_m2": area_m2, "rent_per_m2": 0.0, "humidity": 0.5}


## 有地面格子的场所（店面、仓库，07 §3、§4）：w×h 格，door 是门口那格，counter 是收银台（店面才有）。
func add_room(id: String, type: String, w: int, h: int, extra: Dictionary = {}) -> void:
	add_location(id, type, float(w * h))
	locations[id]["grid"] = [w, h]
	for k in extra:
		locations[id][k] = extra[k]


func room_size(location_id: String) -> Vector2i:
	var g: Array = locations.get(location_id, {}).get("grid", [0, 0])
	return Vector2i(int(g[0]), int(g[1]))


func room_cell(location_id: String, key: String) -> Vector2i:
	var c: Array = locations.get(location_id, {}).get(key, [-1, -1])
	return Vector2i(int(c[0]), int(c[1]))


func new_package_id() -> String:
	var id := "pk_%06d" % _next_pkg
	_next_pkg += 1
	return id


func create_package(kind: String) -> Package:
	var p := Package.new()
	p.id = new_package_id()
	p.kind = kind
	return p


## 地堆（07 §3）：直接堆在某格地面上的箱、包。第一次往那格放东西时才建槽位。
const FLOOR_CAPACITY := 12


func floor_slot(location_id: String, cell: Vector2i) -> Slot:
	for sl in slots_in(location_id, "Floor"):
		if sl.grid_pos == cell:
			return sl
	var s := Slot.new()
	s.id = "sl_%04d" % _next_slot
	_next_slot += 1
	s.type = "Floor"
	s.location_id = location_id
	s.grid_pos = cell
	s.access_cost = 1.5
	s.stack.max_height = 0
	s.pkg_capacity = FLOOR_CAPACITY
	slots[s.id] = s
	return s


## 地上空了的格子不留着（点过的空地会临时建一个地堆格）。
func prune_empty_floors(location_id: String) -> void:
	for sl in slots_in(location_id, "Floor"):
		if sl.packages.is_empty():
			slots.erase(sl.id)


## 某格上摆着的设备实例 ID（没有返回空）。设备按 def 的 size 占 w×h 格。
func equipment_at(location_id: String, cell: Vector2i) -> String:
	for eid in equipment:
		var e: Dictionary = equipment[eid]
		if e["location_id"] != location_id or not e.has("pos"):
			continue
		var sz := equipment_size(eid)
		var p := Vector2i(int(e["pos"][0]), int(e["pos"][1]))
		if cell.x >= p.x and cell.x < p.x + sz.x and cell.y >= p.y and cell.y < p.y + sz.y:
			return eid
	return ""


func equipment_size(eid: String) -> Vector2i:
	var def: Dictionary = DataDB.equipment().get(equipment[eid]["def_id"], {})
	var sz: Array = def.get("size", [1, 1])
	return Vector2i(int(sz[0]), int(sz[1]))


func equipment_slots(eid: String) -> Array[Slot]:
	var out: Array[Slot] = []
	for sid in equipment.get(eid, {}).get("slot_ids", []):
		out.append(slots[sid])
	return out


func equipment_in(location_id: String) -> Array:
	var out: Array = []
	for eid in equipment:
		if equipment[eid]["location_id"] == location_id:
			out.append(eid)
	out.sort()
	return out


## 拆掉一件设备（卖掉或搬走前）。上面还有货就不能拆，返回 false。
func remove_equipment(eid: String) -> bool:
	if not equipment.has(eid):
		return false
	for sl in equipment_slots(eid):
		if sl.stack.height() > 0 or not sl.stack.collapsed_pile.is_empty() or not sl.packages.is_empty():
			return false
	for sid in equipment[eid]["slot_ids"]:
		slots.erase(sid)
	equipment.erase(eid)
	return true


func slots_in(location_id: String, type: String = "") -> Array[Slot]:
	var out: Array[Slot] = []
	for sid in slots:
		var s: Slot = slots[sid]
		if s.location_id == location_id and (type == "" or s.type == type):
			out.append(s)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func slots_of_type(type: String) -> Array[Slot]:
	var out: Array[Slot] = []
	for sid in slots:
		if slots[sid].type == type:
			out.append(slots[sid])
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## 玩家手上：从堆顶拿下来、从中间抽出来的货先拿在手里，再放到某个堆顶（03 §4）。
## 用到时才创建，老存档里没有也没关系。
const HAND_ID := "hand_player"


## 每次都按【搬运】重设上限（02 §2.10）：散货 hand_items 条，或 hand_boxes 箱，或 hand_packs 包，三选一。
## 存档里存的旧上限不作数。
func hand() -> Slot:
	if not slots.has(HAND_ID):
		var h := Slot.new()
		h.id = HAND_ID
		h.type = "Hand"
		h.location_id = "player"
		slots[h.id] = h
	var m := SkillSystem.carry_mods(player if player != null else PlayerState.new())
	var hd: Slot = slots[HAND_ID]
	hd.stack.max_height = int(m["hand_items"])
	hd.kind_limits = {"box": int(m["hand_boxes"]), "pack": int(m["hand_packs"])}
	hd.pkg_capacity = maxi(int(m["hand_boxes"]) * int(Package.UNITS["box"]), int(m["hand_packs"]))
	return hd


## 手推车上的散货篓最多放几条（07 §2.1）。像行囊一样是软的：只拿顶放顶，不玩抽取、不塌。
const CART_BASKET := 10


## 手推车（开店后才有，没有返回 null）。散货篓上限每次重设，老存档里存的 0 不作数。
func cart() -> Slot:
	var carts := slots_of_type("Cart")
	if carts.is_empty():
		return null
	carts[0].stack.max_height = CART_BASKET
	return carts[0]


## 安装设备 = 向场所注入一组槽位（01 §4.9）。返回设备实例 ID。pos 为摆放的格子（店面、仓库里用）。
func install_equipment(def_id: String, location_id: String, pos := Vector2i(-1, -1)) -> String:
	var def: Dictionary = DataDB.equipment().get(def_id, {})
	if def.is_empty():
		push_error("未知设备 %s" % def_id)
		return ""
	var eid := "eq_%04d" % _next_equip
	_next_equip += 1
	var slot_ids: Array = []
	for spec in def.get("provides_slots", []):
		for i in int(spec.get("count", 1)):
			var s := Slot.new()
			s.id = "sl_%04d" % _next_slot
			_next_slot += 1
			s.type = spec["type"]
			s.location_id = location_id
			s.grid_pos = Vector2i(i, 0)
			s.display_score = float(spec.get("display_score", 0.0))
			s.access_cost = float(spec.get("access_cost", 1.0))
			s.equipment_id = eid
			s.stack.max_height = int(spec.get("max_height", 4))
			s.pkg_capacity = int(spec.get("pkg_capacity", 0))
			slots[s.id] = s
			slot_ids.append(s.id)
	equipment[eid] = {"def_id": def_id, "location_id": location_id, "slot_ids": slot_ids}
	if pos.x >= 0:
		equipment[eid]["pos"] = [pos.x, pos.y]
		for sid in slot_ids:
			slots[sid].grid_pos = pos
	return eid


## 把设备（及其槽位）搬到另一个场所，例如摊位板从家里带到街上。
func move_equipment(eid: String, location_id: String) -> void:
	if not equipment.has(eid):
		return
	equipment[eid]["location_id"] = location_id
	for sid in equipment[eid]["slot_ids"]:
		slots[sid].location_id = location_id


## 全部围巾，包括箱里、包里的。
func all_items() -> Array[ScarfItem]:
	var out: Array[ScarfItem] = []
	for sid in slots:
		out.append_array(slots[sid].stack.items)
		out.append_array(slots[sid].stack.collapsed_pile)
		for p in slots[sid].packages:
			out.append_array(p.all_items())
	return out


## 某个整箱 / 整包现在在哪：{slot_id, index, box_id}。box_id 非空表示它是箱里的一包。找不到返回空。
func locate_package(pkg_id: String) -> Dictionary:
	for sid in slots:
		var pk: Array[Package] = slots[sid].packages
		for i in pk.size():
			if pk[i].id == pkg_id:
				return {"slot_id": sid, "index": i, "box_id": ""}
			for p in pk[i].packs:
				if p.id == pkg_id:
					return {"slot_id": sid, "index": i, "box_id": pk[i].id}
	return {}


func find_package(pkg_id: String) -> Package:
	var loc := locate_package(pkg_id)
	if loc.is_empty():
		return null
	var outer: Package = slots[loc["slot_id"]].packages[loc["index"]]
	if loc["box_id"] == "":
		return outer
	for p in outer.packs:
		if p.id == pkg_id:
			return p
	return null


func count_items(location_id: String = "", type: String = "") -> int:
	var n := 0
	for sid in slots:
		var s: Slot = slots[sid]
		if (location_id == "" or s.location_id == location_id) and (type == "" or s.type == type):
			n += s.stack.height()
	return n


func to_dict() -> Dictionary:
	var sd := {}
	for sid in slots:
		sd[sid] = slots[sid].to_dict()
	return {
		"locations": locations.duplicate(true),
		"slots": sd,
		"equipment": equipment.duplicate(true),
		"next_item": _next_item, "next_slot": _next_slot, "next_equip": _next_equip, "next_pkg": _next_pkg,
	}


static func from_dict(d: Dictionary) -> Inventory:
	var inv := Inventory.new()
	inv.locations = d.get("locations", {})
	for sid in d.get("slots", {}):
		inv.slots[sid] = Slot.from_dict(d["slots"][sid])
	inv.equipment = d.get("equipment", {})
	inv._next_item = int(d.get("next_item", 1))
	inv._next_slot = int(d.get("next_slot", 1))
	inv._next_equip = int(d.get("next_equip", 1))
	inv._next_pkg = int(d.get("next_pkg", 1))
	return inv
