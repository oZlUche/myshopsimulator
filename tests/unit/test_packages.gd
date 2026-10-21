extends TestCase
## 整箱整包（07 §1–§2）、店面与仓库的格子（07 §3–§4）、店面营业。


func _preview() -> GameState:
	var s := GameState.new_game(21)
	PeriodRunner.begin_period(s)
	ShopSetup.start_preview(s)
	return s


func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)), "", true)


func test_shipment_packs_and_boxes() -> void:
	var s := GameState.new_game(3)
	var lines := [
		{"pattern": "plaid", "material": "wool", "mix": "single", "color": "red", "packs": 12},
		{"pattern": "dot", "material": "chiffon", "mix": "mixed", "packs": 5},
	]
	var colors := {"red": 1.0, "navy": 1.0, "beige": 1.0, "black": 1.0, "grey": 1.0, "camel": 1.0}
	var boxes := Wholesale.make_shipment(s.inventory, lines, colors, s.rng, 0)
	assert_eq(boxes.size(), 2, "17 包装 2 箱")
	assert_eq(boxes[0].packs.size(), Wholesale.BOX_PACKS)
	assert_eq(boxes[1].packs.size(), 7)
	assert_eq(boxes[1].waybill["piece"], 2)
	assert_eq(boxes[1].waybill["of"], 2)
	assert_true(float(boxes[0].waybill["weight"]) > 10.0)
	for b in boxes:
		assert_true(b.is_box() and b.sealed)
		for p in b.packs:
			assert_eq(p.items.size(), Wholesale.PACK_SIZE)
			var colors_in := {}
			for it in p.items:
				var sku := DataDB.sku(it.sku_id)
				assert_eq(sku["pattern"], p.sticker["pattern"], "一包是同一款")
				assert_eq(sku["material"], p.sticker["material"])
				colors_in[sku["color"]] = true
				assert_near(float(it.provenance["unit_cost"]), Wholesale.unit_cost(p.sticker["pattern"], p.sticker["material"], p.mix))
			if p.mix == "single":
				assert_eq(colors_in.keys(), ["red"], "单色包整包一个色")
			else:
				assert_true(colors_in.size() >= 3 and colors_in.size() <= 5, "混色包 3–5 种色：%d" % colors_in.size())
	assert_true(Wholesale.unit_cost("dot", "chiffon", "mixed") < Wholesale.unit_cost("dot", "chiffon", "single"), "混色包便宜")


func test_hand_carries_one_box_or_three_packs() -> void:
	var s := _preview()
	var api := ActionAPI.new(s)
	var unload := s.inventory.floor_slot(ShopSetup.WAREHOUSE, Vector2i(2, 4))
	assert_eq(unload.packages.size(), 4, "第一格卸了 4 箱")
	assert_true(api.take_package(unload.id)["ok"])
	assert_true(not api.take_package(unload.id)["ok"], "抱着一箱就抱不了第二箱")
	var empty_cell := s.inventory.floor_slot(ShopSetup.WAREHOUSE, Vector2i(4, 2))
	assert_true(api.put_package(empty_cell.id)["ok"])
	assert_true(api.open_box(empty_cell.id))
	assert_true(not api.open_box(empty_cell.id), "拆过的不用再拆")
	for i in 3:
		assert_true(api.take_pack_from_box(empty_cell.id)["ok"], "第 %d 包" % (i + 1))
	assert_true(not api.take_pack_from_box(empty_cell.id)["ok"], "最多抱 3 包")
	assert_eq(empty_cell.packages[0].packs.size(), Wholesale.BOX_PACKS - 3)
	assert_true(api.take_top_to_hand(empty_cell.id) == null, "抱着包就不能再拿散货")
	# 地堆最高 4 箱
	var pile := s.inventory.floor_slot(ShopSetup.WAREHOUSE, Vector2i(5, 2))
	for i in 3:
		api.put_package(pile.id)
	assert_eq(pile.package_units(), 3)
	var box := s.inventory.create_package("box")
	for i in 4:
		assert_eq(pile.can_hold(box), pile.package_units() + 3 <= Inventory.FLOOR_CAPACITY)
		pile.packages.append(s.inventory.create_package("box"))
	assert_true(not pile.can_hold(box))


func test_unpack_keeps_order_and_leaves_overflow_in_pack() -> void:
	var s := _preview()
	var api := ActionAPI.new(s)
	var cab: Slot = s.inventory.slots_in(ShopSetup.SHOP, "ShopBackroom")[0]
	var shelf: Slot = s.inventory.slots_in(ShopSetup.SHOP, "ShopDisplay")[0]
	assert_eq(cab.packages.size(), 3, "货柜里先放了 3 包")
	var pack: Package = cab.packages[-1]
	var order := pack.items.map(func(i): return i.id)
	var r := api.unpack_to(cab.id, shelf.id)
	assert_true(r["ok"])
	assert_eq(r["moved"], shelf.stack.max_height)
	assert_eq(r["left"], Wholesale.PACK_SIZE - shelf.stack.max_height)
	assert_eq(shelf.stack.items.map(func(i): return i.id), order.slice(0, shelf.stack.max_height), "袋底的在堆底")
	assert_true(not pack.sealed, "撕开的包")
	assert_eq(cab.packages.size(), 3, "没倒完的包还在货柜里")
	# 剩下的倒到另外两格，倒空了包就没了
	var shelves := s.inventory.slots_in(ShopSetup.SHOP, "ShopDisplay")
	api.unpack_to(cab.id, shelves[1].id)
	api.unpack_to(cab.id, shelves[2].id)
	assert_eq(cab.packages.size(), 2)
	assert_true(not api.unpack_to(cab.id, s.inventory.floor_slot(ShopSetup.SHOP, Vector2i(0, 0)).id)["ok"], "地堆不放散货")
	# 散货和整包不混放
	assert_true(not shelves[0].can_hold(cab.packages[-1]))
	assert_true(not api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), cab.id), "放着整包的格子不放散货")


func test_preview_inventory_and_lookup() -> void:
	var s := _preview()
	assert_eq(s.player.phase, "shop")
	assert_eq(s.inventory.all_items().size(), 6 * Wholesale.BOX_PACKS * Wholesale.PACK_SIZE, "6 箱 600 条都算在库存里")
	var cab: Slot = s.inventory.slots_in(ShopSetup.SHOP, "ShopBackroom")[0]
	var p: Package = cab.packages[0]
	var loc := s.inventory.locate_package(p.id)
	assert_eq(loc["slot_id"], cab.id)
	var box: Package = s.inventory.floor_slot(ShopSetup.WAREHOUSE, Vector2i(2, 4)).packages[0]
	var inner: Package = box.packs[3]
	assert_eq(s.inventory.locate_package(inner.id)["box_id"], box.id)
	assert_true(s.inventory.find_package(inner.id) == inner)
	var api := ActionAPI.new(s)
	api.write_label(box.id, "红格子羊毛")
	assert_eq(s.knowledge.labels[box.id], "红格子羊毛")
	api.write_label(box.id, " ")
	assert_true(not s.knowledge.labels.has(box.id), "空标签 = 擦掉")
	var seen := api.look_at_pack(p)
	assert_true(s.knowledge.perceived.has(p.top_item().id))
	assert_true(String(seen["sku_guess"]).begins_with("scarf_"))


func test_room_grid_walking_and_placement() -> void:
	var s := _preview()
	var inv := s.inventory
	var stand := ShopSetup.stand_cell(inv)
	assert_eq(RoomGrid.steps_to(inv, ShopSetup.SHOP, stand, Vector2i(6, 0)), 2, "货柜在收银台后面两步")
	assert_true(RoomGrid.steps_to(inv, ShopSetup.SHOP, stand, Vector2i(1, 1)) > RoomGrid.steps_to(inv, ShopSetup.SHOP, stand, Vector2i(3, 1)), "远的货架走得久")
	assert_eq(RoomGrid.can_place(inv, ShopSetup.SHOP, "shop_window", Vector2i(2, 2)), "橱窗只能摆在临街那排")
	assert_eq(RoomGrid.can_place(inv, ShopSetup.SHOP, "shop_window", Vector2i(5, 4)), "")
	assert_true(RoomGrid.can_place(inv, ShopSetup.SHOP, "shop_shelf", Vector2i(3, 4)) != "", "门口不能摆")
	assert_true(RoomGrid.can_place(inv, ShopSetup.SHOP, "shop_shelf", Vector2i(1, 1)) != "", "格子被占了")
	assert_eq(RoomGrid.unreachable(inv, ShopSetup.SHOP), [])
	# 把门口两侧和里面一排堵死，后面的货架就走不到了
	for c in [Vector2i(2, 4), Vector2i(4, 4), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]:
		inv.install_equipment("shop_shelf", ShopSetup.SHOP, c)
	assert_true(RoomGrid.unreachable(inv, ShopSetup.SHOP).size() > 0)


func test_shop_session_sells_from_displays() -> void:
	var s := _preview()
	var api := ActionAPI.new(s)
	var cab: Slot = s.inventory.slots_in(ShopSetup.SHOP, "ShopBackroom")[0]
	for sl in s.inventory.slots_in(ShopSetup.SHOP, "ShopDisplay"):
		if not cab.packages.is_empty():
			api.unpack_to(cab.id, sl.id)
	var ss := ShopSession.new(s)
	assert_true(ss.table_goods() > 0)
	for i in 600:
		ss.tick(1.0)
		for v in ss.visitors.duplicate():
			if v["state"] == "asking":
				var h := ss.start_haggle(v)
				if h != null and h.customer_offer > 0.0:
					h.accept_customer_offer()
				elif h != null:
					h.offer_price(h.asking_price * 0.7, s.rng)
				ss.finish(v, h)
	assert_true(int(s.period_stats["traffic"]) > 50, "门口有人流：%d" % int(s.period_stats["traffic"]))
	assert_true(int(s.period_stats["stayed"]) > 0, "有人进店")
	assert_true(int(s.period_stats["sales"]) + ss.visitors.filter(func(v): return v["state"] == "waiting_item").size() > 0 \
		or int(s.period_stats["lost_after_deal"]) > 0, "有人谈成")
	var title := ss.slot_title(s.inventory.slots_in(ShopSetup.SHOP, "ShopDisplay")[1])
	assert_eq(title, "货架 1 第 2 格")
	assert_eq(ShopSession.slot_name(s.inventory, s.inventory.slots_in(ShopSetup.SHOP, "ShopDisplay")[-1]), "橱窗 1 第 2 格")


func test_packages_survive_save_roundtrip() -> void:
	var s := _preview()
	var api := ActionAPI.new(s)
	var unload := s.inventory.floor_slot(ShopSetup.WAREHOUSE, Vector2i(3, 4))
	api.open_box(unload.id)
	api.take_pack_from_box(unload.id)
	api.write_label(unload.packages[-1].id, "二号箱")
	var d := s.to_dict()
	var s2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(_norm(s2.to_dict()), _norm(d))
	var hand := s2.inventory.hand()
	assert_eq(hand.packages.size(), 1)
	assert_eq(hand.packages[0].items.size(), Wholesale.PACK_SIZE)
	assert_eq(s2.inventory.all_items().size(), s.inventory.all_items().size())
	var r := SaveManager.new().load_from_string(JSON.stringify(d))
	assert_true(r["ok"], str(r.get("error", "")))


func test_path_and_equipment_layout_actions() -> void:
	var s := _preview()
	var inv := s.inventory
	var api := ActionAPI.new(s)
	var stand := ShopSetup.stand_cell(inv)
	var p := RoomGrid.path(inv, ShopSetup.SHOP, stand, Vector2i(6, 0))
	assert_eq(p.size() - 1, RoomGrid.steps_to(inv, ShopSetup.SHOP, stand, Vector2i(6, 0)), "路线和步数一致")
	assert_eq(p[0], stand)
	for i in range(1, p.size()):
		var d := (p[i] - p[i - 1]).abs()
		assert_eq(d.x + d.y, 1, "一步一格")
		assert_true(RoomGrid.walkable(inv, ShopSetup.SHOP, p[i]))
	assert_eq(RoomGrid.path(inv, ShopSetup.SHOP, Vector2i(6, 1), Vector2i(6, 0)), [Vector2i(6, 1)], "已经在旁边")
	assert_eq(RoomGrid.path(inv, ShopSetup.SHOP, stand, Vector2i(3, 4), true).back(), Vector2i(3, 4), "走到门口那格上")
	# 买、挪、卖设备
	var cash := s.player.cash
	assert_true(not api.buy_equipment("shop_window", ShopSetup.SHOP, Vector2i(2, 2))["ok"], "橱窗摆不进里面")
	assert_true(not api.buy_equipment("warehouse_rack", ShopSetup.SHOP, Vector2i(2, 2))["ok"], "仓库货架不进店")
	var r := api.buy_equipment("mannequin", ShopSetup.SHOP, Vector2i(5, 1))
	assert_true(r["ok"])
	assert_near(s.player.cash, cash - 400.0)
	assert_eq(inv.equipment_at(ShopSetup.SHOP, Vector2i(5, 1)), r["equipment_id"])
	assert_true(api.move_equipment(r["equipment_id"], Vector2i(4, 1))["ok"])
	assert_eq(inv.equipment_at(ShopSetup.SHOP, Vector2i(4, 1)), r["equipment_id"])
	assert_true(not api.move_equipment(r["equipment_id"], Vector2i(3, 1))["ok"], "占着的格不能挪过去")
	var counter := inv.equipment_at(ShopSetup.SHOP, Vector2i(5, 3))
	assert_true(not api.move_equipment(counter, Vector2i(5, 2))["ok"], "收银台不动")
	var cab := inv.equipment_at(ShopSetup.SHOP, Vector2i(6, 0))
	assert_true(not api.sell_equipment(cab)["ok"], "货柜里有包，不能卖")
	var sold := api.sell_equipment(r["equipment_id"])
	assert_true(sold["ok"])
	assert_near(float(sold["refund"]), 200.0)
	assert_eq(inv.equipment_at(ShopSetup.SHOP, Vector2i(4, 1)), "")


func test_blocked_displays_are_not_shown_to_customers() -> void:
	var s := _preview()
	var inv := s.inventory
	var ss := ShopSession.new(s)
	var n := ss.display_slots().size()
	# 用地上的箱子把门口堵上：门两边、门里面那排
	for c in [Vector2i(2, 4), Vector2i(4, 4), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]:
		inv.floor_slot(ShopSetup.SHOP, c).packages.append(inv.create_package("box"))
	ss.refresh_layout()
	assert_true(ss.display_slots().size() < n, "堵住以后客人够不着里面的货架")
	inv.prune_empty_floors(ShopSetup.SHOP)
	assert_eq(inv.slots_in(ShopSetup.SHOP, "Floor").size(), 5, "有箱子的地堆留着")


func test_open_pack_and_pass_time() -> void:
	var s := _preview()
	var api := ActionAPI.new(s)
	var cab: Slot = s.inventory.slots_in(ShopSetup.SHOP, "ShopBackroom")[0]
	assert_true(api.take_from_open_pack(cab.id) == null, "封着的包拿不出来")
	assert_true(api.open_pack(cab.id))
	assert_true(not api.open_pack(cab.id))
	assert_true(api.take_from_open_pack(cab.id) != null)
	assert_eq(cab.packages[-1].items.size(), Wholesale.PACK_SIZE - 1)
	ShopSession.pass_time(s, StallSession.PERIOD_SECONDS * 0.25)
	assert_near(s.clock.time_of_period, 0.25)


func test_preview_rooms_carry_rent_contract() -> void:
	var s := GameState.new_game(3)
	s.economy.rent_index_target = 1.1
	ShopSetup.rent_rooms(s)
	var c: Dictionary = s.inventory.locations[ShopSetup.SHOP]["rent_contract"]
	assert_near(float(c["rent_per_m2_nominal"]), 6.6, 0.001, "签约单价 = 实际单价 × ρ_target")
	assert_eq(int(c["end_period"]) - int(c["start_period"]) + 1, ShopSetup.RENT_TERM, "36 旬一签")
