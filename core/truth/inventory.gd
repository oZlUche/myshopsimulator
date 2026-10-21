class_name Inventory
extends RefCounted
## 库存物理模型（01 §4.1）：场所、槽位、设备实例与全部围巾。所有模块的读写底座。

## {location_id: {id, type, area_m2, rent_per_m2, humidity}}
var locations: Dictionary = {}
## {slot_id: Slot}
var slots: Dictionary = {}
## {equipment_instance_id: {def_id, location_id, slot_ids}}
var equipment: Dictionary = {}
var _next_item := 1
var _next_slot := 1
var _next_equip := 1


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
const HAND_MAX := 3


func hand() -> Slot:
	if not slots.has(HAND_ID):
		var h := Slot.new()
		h.id = HAND_ID
		h.type = "Hand"
		h.location_id = "player"
		h.stack.max_height = HAND_MAX
		slots[h.id] = h
	return slots[HAND_ID]


## 安装设备 = 向场所注入一组槽位（01 §4.9）。返回设备实例 ID。
func install_equipment(def_id: String, location_id: String) -> String:
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
			slots[s.id] = s
			slot_ids.append(s.id)
	equipment[eid] = {"def_id": def_id, "location_id": location_id, "slot_ids": slot_ids}
	return eid


## 把设备（及其槽位）搬到另一个场所，例如摊位板从家里带到街上。
func move_equipment(eid: String, location_id: String) -> void:
	if not equipment.has(eid):
		return
	equipment[eid]["location_id"] = location_id
	for sid in equipment[eid]["slot_ids"]:
		slots[sid].location_id = location_id


func all_items() -> Array[ScarfItem]:
	var out: Array[ScarfItem] = []
	for sid in slots:
		out.append_array(slots[sid].stack.items)
		out.append_array(slots[sid].stack.collapsed_pile)
	return out


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
		"next_item": _next_item, "next_slot": _next_slot, "next_equip": _next_equip,
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
	return inv
