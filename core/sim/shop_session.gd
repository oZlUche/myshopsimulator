class_name ShopSession
extends StallSession
## 店面营业（07 §4.2）：客人逻辑、讲价、交货全部沿用摆摊，只换场地——
## 看得到的是店里的展架、橱窗、模特（ShopDisplay），货柜（ShopBackroom）客人看不到；
## 进店的人 = 门口人流 × 橱窗吸引。

const LOC := "shop"
## 门口人流：每秒走过多少人（再乘一天里的起伏曲线）
const DEFAULT_TRAFFIC := 0.45


## 门口走不到的设备（被别的设备或地上的箱子堵住了），客人看不到、拿不到（07 §4.1）。
var _blocked: Dictionary = {}


func _init(state: GameState, returning: Variant = null) -> void:
	super(state, NAN, returning)
	refresh_layout()


## 摆设备、地上堆箱子以后重新算一遍哪些设备走不到。
func refresh_layout() -> void:
	_blocked.clear()
	for eid in RoomGrid.unreachable(s.inventory, LOC):
		_blocked[eid] = true


## 关着门、在仓库干活、在路上：时间照走，但没有客人。
static func pass_time(state: GameState, dt: float) -> void:
	state.clock.time_of_period = minf(1.0, state.clock.time_of_period + dt / PERIOD_SECONDS)


func display_slots() -> Array[Slot]:
	var out: Array[Slot] = []
	for sl in s.inventory.slots_in(LOC, "ShopDisplay"):
		if not _blocked.has(sl.equipment_id):
			out.append(sl)
	return out


func is_display(sl: Slot) -> bool:
	return sl.type == "ShopDisplay" and sl.location_id == LOC


func storage_slots() -> Array[Slot]:
	return s.inventory.slots_in(LOC, "ShopBackroom")


## 「货架 2 第 1 格」「橱窗 1 第 2 格」。
func slot_title(sl: Slot) -> String:
	return ShopSession.slot_name(s.inventory, sl)


static func slot_name(inv: Inventory, sl: Slot) -> String:
	if sl.equipment_id == "" or not inv.equipment.has(sl.equipment_id):
		return "地上"
	var e: Dictionary = inv.equipment[sl.equipment_id]
	var def: Dictionary = DataDB.equipment().get(e["def_id"], {})
	var n := 1
	for eid in inv.equipment_in(e["location_id"]):
		if eid == sl.equipment_id:
			break
		if inv.equipment[eid]["def_id"] == e["def_id"]:
			n += 1
	var ids: Array = e["slot_ids"]
	if ids.size() <= 1:
		return "%s %d" % [def.get("name", "?"), n]
	return "%s %d 第 %d 格" % [def.get("name", "?"), n, ids.find(sl.id) + 1]


func spawn_rate(t: float) -> float:
	return float(s.inventory.locations.get(LOC, {}).get("traffic", DEFAULT_TRAFFIC)) * Street.time_curve(t)


## 橱窗里摆满了、模特穿上了，路过的人更愿意进来（对应摆摊的吆喝，07 §4.2）。
func venue_stay_mult() -> float:
	var cap := 0
	var filled := 0
	for sl in display_slots():
		var def_id: String = s.inventory.equipment.get(sl.equipment_id, {}).get("def_id", "")
		if DataDB.equipment().get(def_id, {}).get("street_visible", false) or def_id == "mannequin":
			cap += sl.stack.max_height
			filled += sl.stack.height()
	var window := float(filled) / cap if cap > 0 else 0.0
	return 0.7 + 0.5 * window


## 店里客人站着逛，不按摊位那样排开，热闹程度按人数算得更平缓。
func heat() -> float:
	return clampf(0.1 + 0.2 * visitors.size() + 0.015 * table_goods(), 0.1, 1.0)
