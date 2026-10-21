class_name Slot
extends RefCounted
## 持有一个货堆的位置（01 §4.1）。

const TYPES := ["WarehouseShelf", "ShopBackroom", "ShopDisplay", "CarTrunk", "StallTable", "Bag", "Hand"]

var id: String
var type: String
var location_id: String = ""
var grid_pos: Vector2i = Vector2i.ZERO
var display_score: float = 0.0
## 拿取耗时系数（走过去 + 翻找）。
var access_cost: float = 1.0
## 提供该槽位的设备实例 ID（无则为空）。
var equipment_id: String = ""
var stack := ItemStack.new()


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "location_id": location_id,
		"grid_pos": [grid_pos.x, grid_pos.y],
		"display_score": display_score, "access_cost": access_cost,
		"equipment_id": equipment_id,
		"stack": stack.to_dict(),
	}


static func from_dict(d: Dictionary) -> Slot:
	var s := Slot.new()
	s.id = str(d.get("id", ""))
	s.type = str(d.get("type", "Bag"))
	s.location_id = str(d.get("location_id", ""))
	var gp: Array = d.get("grid_pos", [0, 0])
	s.grid_pos = Vector2i(int(gp[0]), int(gp[1]))
	s.display_score = float(d.get("display_score", 0.0))
	s.access_cost = float(d.get("access_cost", 1.0))
	s.equipment_id = str(d.get("equipment_id", ""))
	s.stack = ItemStack.from_dict(d.get("stack", {}))
	return s
