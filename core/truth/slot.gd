class_name Slot
extends RefCounted
## 持有一个货堆的位置（01 §4.1）。

const TYPES := ["WarehouseShelf", "ShopBackroom", "ShopDisplay", "CarTrunk", "StallTable", "Bag", "Hand", "Floor", "Cart"]

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
## 整箱、整包（07 §1）：下标 0 在最下面，只能动最上面那个。一个槽位里散货和整包不混放，
## 手推车除外：车板上放箱包，车上另有一个散货篓（stack），两样可以同时有（07 §2.1，见 mixes()）。
var packages: Array[Package] = []
## 能放多少整箱整包（按 Package.UNITS 计，箱 3、包 1）；0 = 不放整包
var pkg_capacity: int = 0
## 手上按形态各自限数 {box: n, pack: n}，箱和包不混拿（03 §4、02 §2.10）；空 = 按 pkg_capacity 的单位算。
## 不存档，Inventory.hand() 每次按【搬运】重设。
var kind_limits: Dictionary = {}


func package_units() -> int:
	var n := 0
	for p in packages:
		n += p.units()
	return n


func top_package() -> Package:
	return null if packages.is_empty() else packages[-1]


## 箱包和散货能不能同时放：只有手推车可以（车板 + 散货篓）。
func mixes() -> bool:
	return type == "Cart"


## 这个包 / 箱能不能放上来：容量够，而且这里没有散货（手推车不管散货篓）。
func can_hold(p: Package) -> bool:
	if pkg_capacity <= 0:
		return false
	if not mixes() and (stack.height() > 0 or not stack.collapsed_pile.is_empty()):
		return false
	if not kind_limits.is_empty():
		for q in packages:
			if q.kind != p.kind:
				return false
		return packages.size() < int(kind_limits.get(p.kind, 0))
	return package_units() + p.units() <= pkg_capacity


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "location_id": location_id,
		"grid_pos": [grid_pos.x, grid_pos.y],
		"display_score": display_score, "access_cost": access_cost,
		"equipment_id": equipment_id,
		"stack": stack.to_dict(),
		"packages": packages.map(func(p): return p.to_dict()),
		"pkg_capacity": pkg_capacity,
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
	for x in d.get("packages", []):
		s.packages.append(Package.from_dict(x))
	s.pkg_capacity = int(d.get("pkg_capacity", 0))
	return s
