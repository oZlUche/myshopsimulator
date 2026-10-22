extends TestCase
## 手推车 = 移动的「手上」（07 §2.1）：推起 / 停下、车上能装多少、停车不堵路、存档。


func _preview() -> GameState:
	var s := GameState.new_game(21)
	PeriodRunner.begin_period(s)
	ShopSetup.start_preview(s)
	return s


func test_preview_cart_parks_in_warehouse() -> void:
	var s := _preview()
	var inv := s.inventory
	var cart := inv.cart()
	assert_true(cart != null)
	assert_eq(cart.stack.max_height, Inventory.CART_BASKET, "散货篓 10 条")
	assert_eq(s.player.cart_room, ShopSetup.WAREHOUSE)
	assert_true(not s.player.pushing_cart)
	assert_eq(RoomGrid.can_park(inv, ShopSetup.WAREHOUSE, s.player.cart_cell), "这格有东西，停不下", "停着的车占着那格")
	assert_true(not RoomGrid.walkable(inv, ShopSetup.WAREHOUSE, s.player.cart_cell), "停着的车绕着走")
	assert_true(RoomGrid.can_place(inv, ShopSetup.WAREHOUSE, "warehouse_rack", s.player.cart_cell) != "", "车停的格不能摆货架")
	assert_eq(ActionAPI.new(s).carrier().id, inv.hand().id, "没推车时拿到手上")


func test_pushing_cart_makes_it_the_carrier() -> void:
	var s := _preview()
	var inv := s.inventory
	var api := ActionAPI.new(s)
	var cart := inv.cart()
	var unload := inv.floor_slot(ShopSetup.WAREHOUSE, Vector2i(2, 4))
	assert_true(api.take_package(unload.id)["ok"], "先抱一箱在手上")
	var r := api.push_cart()
	assert_true(r["ok"])
	assert_eq(int(r["moved"]), 1, "手上那箱顺手放到车上")
	assert_true(inv.hand().packages.is_empty())
	assert_eq(api.carrier().id, cart.id, "推车时车就是手上")
	assert_near(api.walk_speed_mult(), 0.8, 0.0001, "推车走路 ×0.8")
	assert_true(api.take_package(unload.id)["ok"], "第二箱直接上车")
	var third := api.take_package(unload.id)
	assert_true(not third["ok"], "一车最多 2 箱")
	assert_true(str(third["reason"]).begins_with("车上放不下了"), third["reason"])
	# 卸一箱到地上，再从拆开的箱里拿 3 包上车：1 箱 + 3 包 = 6 单位
	var spot := inv.floor_slot(ShopSetup.WAREHOUSE, Vector2i(4, 2))
	assert_true(api.put_package(spot.id)["ok"], "点格空处从车上卸")
	assert_true(api.open_box(spot.id))
	for i in 3:
		assert_true(api.take_pack_from_box(spot.id)["ok"], "第 %d 包上车" % (i + 1))
	assert_eq(cart.package_units(), 6)
	assert_true(not api.take_pack_from_box(spot.id)["ok"], "满 6 单位")
	# 箱包和散货篓可以同时有：车上那包撕开，一条条拿进篓里
	assert_true(api.open_pack(cart.id))
	var it := api.take_from_open_pack(cart.id)
	assert_true(it != null and cart.stack.index_of(it.id) >= 0, "开口包里拿一条进篓")
	assert_eq(api.hand_room(), Inventory.CART_BASKET - 1)
	# 散货：店里货架上摆几条，推着车从堆顶拆，进篓
	var display: Slot = inv.slots_in(ShopSetup.SHOP, "ShopDisplay")[0]
	for k in 3:
		api.place_on_top(inv.create_item("scarf_solid_red_wool"), display.id)
	assert_true(api.take_top_to_hand(display.id, 3) != null)
	assert_eq(cart.stack.height(), 4, "3 条拆进篓里")
	assert_eq(api.place_from_carrier(display.id, 2), 2, "从篓里批量放回货架")
	assert_eq(display.stack.height(), 2)


func test_parking_rules_and_no_blocking() -> void:
	var s := _preview()
	var inv := s.inventory
	var api := ActionAPI.new(s)
	assert_true(api.push_cart()["ok"])
	var door := inv.room_cell(ShopSetup.SHOP, "door")
	var stand := inv.room_cell(ShopSetup.SHOP, "stand")
	assert_true(not api.park_cart(ShopSetup.SHOP, door)["ok"], "门口不能停")
	assert_true(not api.park_cart(ShopSetup.SHOP, stand)["ok"], "收银台后面不能停")
	assert_true(not api.park_cart(ShopSetup.SHOP, Vector2i(1, 1))["ok"], "货架那格停不下")
	assert_true(s.player.pushing_cart, "没停成还推着")
	# 模特摆在 (5,1)：货柜前 (6,1) 只剩 (6,2) 一条路，车停 (6,2) 会把人堵死
	inv.install_equipment("mannequin", ShopSetup.SHOP, Vector2i(5, 1))
	assert_true(not RoomGrid.parking_keeps_paths(inv, ShopSetup.SHOP, Vector2i(6, 2), Vector2i(6, 1)), "会堵路")
	var near := RoomGrid.nearest_parking(inv, ShopSetup.SHOP, Vector2i(6, 1))
	assert_true(near.x >= 0 and near != Vector2i(6, 2), "找别的格停：%s" % near)
	assert_true(RoomGrid.parking_keeps_paths(inv, ShopSetup.SHOP, near, Vector2i(6, 1)))
	assert_true(api.park_cart(ShopSetup.SHOP, near, "se")["ok"])
	assert_eq(s.player.cart_room, ShopSetup.SHOP)
	assert_eq(s.player.cart_facing, "se")
	assert_true(not RoomGrid.walkable(inv, ShopSetup.SHOP, near))
	assert_eq(RoomGrid.unreachable(inv, ShopSetup.SHOP), [], "停好的车不挡设备")
	# 推车不进收银台后面
	assert_true(RoomGrid.path(inv, ShopSetup.SHOP, door, stand, true, [stand]).is_empty())


func test_cart_goods_count_for_delivery_lookup() -> void:
	var s := _preview()
	var api := ActionAPI.new(s)
	assert_true(api.push_cart()["ok"])
	var display: Slot = s.inventory.slots_in(ShopSetup.SHOP, "ShopDisplay")[0]
	var it := s.inventory.create_item("scarf_solid_red_wool")
	api.place_on_top(it, display.id)
	api.take_top_to_hand(display.id)
	var ss := ShopSession.new(s)
	var at := ss.locate(it.id)
	assert_eq(at.get("slot_id", ""), s.inventory.cart().id, "车上的货也找得到（交货算手上有）")
	assert_true(not ss.is_display(s.inventory.cart()), "车不是货架，客人不会自己从车上拿")


func test_cart_state_survives_save() -> void:
	var s := _preview()
	var api := ActionAPI.new(s)
	assert_true(api.push_cart()["ok"])
	var unload := s.inventory.floor_slot(ShopSetup.WAREHOUSE, Vector2i(3, 4))
	assert_true(api.take_package(unload.id)["ok"])
	var display: Slot = s.inventory.slots_in(ShopSetup.SHOP, "ShopDisplay")[0]
	api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), display.id)
	api.take_top_to_hand(display.id)
	assert_true(api.park_cart(ShopSetup.WAREHOUSE, Vector2i(4, 2), "nw")["ok"])
	var s2 := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(s2.player.cart_room, ShopSetup.WAREHOUSE)
	assert_eq(s2.player.cart_cell, Vector2i(4, 2))
	assert_eq(s2.player.cart_facing, "nw")
	assert_true(not s2.player.pushing_cart)
	var c2 := s2.inventory.cart()
	assert_eq(c2.packages.size(), 1, "车板上的箱")
	assert_eq(c2.stack.height(), 1, "篓里的散货")
	assert_true(not RoomGrid.walkable(s2.inventory, ShopSetup.WAREHOUSE, Vector2i(4, 2)), "读档后车还占着那格")
	# 老存档没有这些字段：不推车、车还没停进哪间屋
	var old := PlayerState.from_dict({"cash": 100.0})
	assert_true(not old.pushing_cart and old.cart_room == "" and old.cart_cell == Vector2i(-1, -1))
