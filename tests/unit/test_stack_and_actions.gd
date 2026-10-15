extends TestCase


func _state() -> GameState:
	var s := GameState.new_game(42)
	PeriodRunner.begin_period(s)
	return s


func test_purchase_goes_into_bag() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var e: Dictionary = s.supplier_catalog[0]
	var cash := s.player.cash
	var r := api.purchase(e["sku_id"], 2, float(e["unit_price"]))
	assert_true(r["ok"], str(r))
	assert_eq(s.inventory.count_items("player", "Bag"), 2)
	assert_near(s.player.cash, cash - 2.0 * float(e["unit_price"]))


func test_bag_capacity_enforced() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	s.player.cash = 100000.0
	var free := api.bag_free_space()
	var e: Dictionary = s.supplier_catalog[0]
	e["stock"] = free + 5
	var r := api.purchase(e["sku_id"], free + 1, 1.0)
	assert_true(not r["ok"], "超出行囊容量必须失败")


func test_pull_top_never_collapses() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table: Slot = s.inventory.slots_of_type("StallTable")[0]
	for i in 3:
		api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), table.id)
	var r := api.pull_item(table.id, 2, {"angle_deg": 90.0, "point": "center", "early_speed": 5.0, "jerk": 5.0})
	assert_true(not r["collapsed"])
	assert_eq(table.stack.height(), 2)


func test_bad_pull_from_bottom_can_collapse() -> void:
	var p_bad := PullPhysics.collapse_probability(PullPhysics.deviation_from_input({"angle_deg": 90.0, "point": "center", "early_speed": 2.0, "jerk": 1.0}), 3)
	var p_good := PullPhysics.collapse_probability(PullPhysics.deviation_from_input(ActionAPI.CAREFUL_PULL), 3)
	assert_true(p_bad > 0.8, "粗暴抽底部应高概率倒塌 %f" % p_bad)
	assert_true(p_good < 0.15, "规范抽取应低概率倒塌 %f" % p_good)
	assert_eq(PullPhysics.collapse_probability(5.0, 0), 0.0)


func test_collapse_moves_items_above_to_pile() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table: Slot = s.inventory.slots_of_type("StallTable")[0]
	for i in 3:
		api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), table.id)
	var collapsed := false
	for attempt in 50:
		var r := api.pull_item(table.id, 0, {"angle_deg": 90.0, "point": "center", "early_speed": 3.0, "jerk": 2.0})
		if r["collapsed"]:
			collapsed = true
			assert_eq(table.stack.height(), 0)
			assert_eq(table.stack.collapsed_pile.size(), 2)
			break
		# 没塌就复原再试
		api.place_on_top(r["item"], table.id)
		api.restack(table.id, table.stack.items.map(func(i): return i.id))
	assert_true(collapsed, "50 次粗暴抽取至少应塌一次")


func test_disorder() -> void:
	var st := ItemStack.new()
	st.max_height = 10
	for sku in ["a", "a", "b", "b"]:
		st.items.append(ScarfItem.new("x", sku))
	st.recompute_disorder()
	assert_near(st.disorder, 0.0)
	st.items = [] as Array[ScarfItem]
	for sku in ["a", "b", "a", "b"]:
		st.items.append(ScarfItem.new("x", sku))
	st.recompute_disorder()
	assert_near(st.disorder, 1.0)


func test_memory_ring_counts_operations() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	s.player.skills["memory"] = {"level": 1, "invested": 0.0}
	var tables := s.inventory.slots_of_type("StallTable")
	api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), tables[0].id)
	api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), tables[1].id)
	assert_eq(s.knowledge.recent_slots.size(), 1)
	assert_eq(Sampler.memory_tooltip(s.knowledge, tables[0].id, s.player), "", "Lv1 只记最近 1 次")
	assert_true(Sampler.memory_tooltip(s.knowledge, tables[1].id, s.player) != "")


func test_pack_up_returns_goods_to_bag() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table: Slot = s.inventory.slots_of_type("StallTable")[0]
	api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), table.id)
	table.stack.collapsed_pile.append(s.inventory.create_item("scarf_solid_red_wool"))
	var lost := api.pack_up()
	assert_eq(lost, 0)
	assert_eq(s.inventory.count_items("", "StallTable"), 0)
	assert_eq(s.inventory.count_items("player", "Bag"), 2)


func test_buy_equipment_adds_slots() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var before := s.inventory.slots_of_type("StallTable").size()
	var r := api.buy_equipment("stall_board_small", "stall")
	assert_true(r["ok"], str(r))
	assert_eq(s.inventory.slots_of_type("StallTable").size(), before + 4)
	assert_near(s.player.cash, 500.0 - 120.0)
	s.player.cash = 0.0
	assert_true(not api.buy_equipment("bag_extra", "player")["ok"], "没钱买不了")
