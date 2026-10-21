class_name ShopSetup
extends RefCounted
## 开店（01 §8 阶段 1、07）：租下店面和仓库、摆上基础设备、卸货区放一批货。
## 摆摊 → 开店的资金门槛还没定（01 §9），先由"试玩开店（预览）"直接调用。

const SHOP := "shop"
const WAREHOUSE := "warehouse"
const SHOP_SIZE := Vector2i(7, 5)
const WAREHOUSE_SIZE := Vector2i(6, 5)
## 仓库与店之间走一趟（秒，1x）。开车小游戏做好前用手推车代替（07 §3）。
const TRIP_SECONDS := 60.0
const PREVIEW_CASH := 3000.0


## 租下店面（7×5）和仓库（6×5）。临街那排是 gy = h−1，门开在中间。
static func rent_rooms(s: GameState) -> void:
	var inv := s.inventory
	inv.add_room(SHOP, "Shop", SHOP_SIZE.x, SHOP_SIZE.y, {
		"door": [3, 4], "stand": [6, 3], "counter": [5, 3], "traffic": ShopSession.DEFAULT_TRAFFIC, "rent_per_m2": 6.0})
	inv.add_room(WAREHOUSE, "Warehouse", WAREHOUSE_SIZE.x, WAREHOUSE_SIZE.y, {
		"door": [1, 4], "unload": [[2, 4], [3, 4]], "rent_per_m2": 2.0, "humidity": 0.55})
	inv.install_equipment("shop_counter", SHOP, Vector2i(5, 3))


## 预览开局（07 §5）：现金、两个货架、一个货柜、一个橱窗、两个仓库货架、手推车；
## 卸货区 6 箱货，店里货柜里先放 3 包让你马上能上架。
static func start_preview(s: GameState) -> void:
	s.player.phase = "shop"
	s.player.cash = maxf(s.player.cash, PREVIEW_CASH)
	rent_rooms(s)
	var inv := s.inventory
	inv.install_equipment("shop_shelf", SHOP, Vector2i(1, 1))
	inv.install_equipment("shop_shelf", SHOP, Vector2i(3, 1))
	var cab := inv.install_equipment("shop_cabinet", SHOP, Vector2i(6, 0))
	inv.install_equipment("shop_window", SHOP, Vector2i(1, 4))
	inv.install_equipment("warehouse_rack", WAREHOUSE, Vector2i(0, 0))
	inv.install_equipment("warehouse_rack", WAREHOUSE, Vector2i(1, 0))
	inv.install_equipment("hand_cart", "player")
	var lines := preview_order(s)
	var boxes := Wholesale.make_shipment(inv, lines, s.trend_now()["color"], s.rng, s.clock.period, s.econ_now())
	var unload: Array = inv.locations[WAREHOUSE]["unload"]
	for i in boxes.size():
		var cell: Array = unload[mini(i / 4, unload.size() - 1)]
		inv.floor_slot(WAREHOUSE, Vector2i(int(cell[0]), int(cell[1]))).packages.append(boxes[i])
	# 货柜第一格先放 3 包：从最后一箱里拿出来
	var cab_slot: Slot = inv.equipment_slots(cab)[0]
	var last: Package = boxes[-1]
	for i in 3:
		if not last.packs.is_empty():
			cab_slot.packages.append(last.packs.pop_back())
	last.sealed = false
	for b in boxes:
		b.waybill["weight"] = Wholesale.box_weight(b)
	for it in inv.all_items():
		if not s.stall["prices"].has(it.sku_id):
			s.stall["prices"][it.sku_id] = s.list_price(it.sku_id)


## 预览那批货：按眼下流行的图案、本季的材质挑 6 款，单色、混色各半，每款 10 包 → 6 箱。
static func preview_order(s: GameState) -> Array:
	var trend := s.trend_now()
	var econ := s.econ_now()
	var lines: Array = []
	for i in 6:
		var mix := "single" if i % 2 == 0 else "mixed"
		lines.append({"pattern": s.rng.weighted_pick(trend["pattern"]), "material": s.rng.weighted_pick(econ["material_pref"]),
			"mix": mix, "color": s.rng.weighted_pick(trend["color"]), "packs": Wholesale.BOX_PACKS})
	return lines


## 收银台后玩家平时站的格子。
static func stand_cell(inv: Inventory) -> Vector2i:
	return inv.room_cell(SHOP, "stand")
