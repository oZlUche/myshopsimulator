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


func _drag(dir: Vector2, speeds: Array) -> Array:
	var out: Array = []
	var p := Vector2(100, 300)
	var t := 0.0
	out.append({"t": t, "pos": p})
	for v in speeds:
		t += 0.05
		p += dir.normalized() * float(v) * 0.05
		out.append({"t": t, "pos": p})
	return out


func test_drag_good_technique_is_low_deviation() -> void:
	# 从角落斜向 40° 拉，先慢后快
	var speeds := [60, 80, 100, 140, 200, 280, 380, 480, 560, 600]
	var good := PullPhysics.input_from_drag(_drag(Vector2(1, -0.84), speeds), "corner")
	assert_true(absf(float(good["angle_deg"]) - 40.0) < 1.0, str(good))
	var d_good := PullPhysics.deviation_from_input(good)
	# 从中间水平猛拽
	var bad := PullPhysics.input_from_drag(_drag(Vector2(1, 0), [900, 900, 300, 1200, 900, 900]), "center")
	var d_bad := PullPhysics.deviation_from_input(bad)
	assert_true(d_good < 0.3, "好手法偏差应小：%f %s" % [d_good, str(good)])
	assert_true(d_bad > 2.0, "坏手法偏差应大：%f %s" % [d_bad, str(bad)])


func test_partial_pull_stays_out_and_above_keeps_shift() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table: Slot = s.inventory.slots_of_type("StallTable")[0]
	for i in 3:
		api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), table.id)
	# 抽到 30% 停手：货停在外面，上面两层被带歪，越往上越歪
	api.record_pull_progress(table.id, 0, -0.3, 0.06, 0.3, -0.3)
	var st := table.stack
	assert_near(st.items[0].pull_out, -0.3)
	assert_true(st.items[1].shift < 0.0 and st.items[2].shift < st.items[1].shift, "%f %f" % [st.items[1].shift, st.items[2].shift])
	# 存档读回来还在
	var back := ItemStack.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	assert_near(back.items[0].pull_out, -0.3)
	assert_near(back.items[2].shift, st.items[2].shift)
	# 抽出后剩下的货保持带歪的位置
	var shift_top := st.items[2].shift
	var r := api.pull_item(table.id, 0, {"d": 0.2})
	assert_true(r["item"] != null)
	assert_near(r["item"].pull_out, 0.0)
	if not r["collapsed"]:
		assert_near(st.items[1].shift, shift_top)
	# 理货才归位
	api.restack(table.id, st.items.map(func(it): return it.id))
	for it in st.items:
		assert_near(it.shift, 0.0)


func test_old_item_without_pull_fields_loads() -> void:
	var it := ScarfItem.from_dict({"id": "i1", "sku_id": "scarf_solid_red_wool"})
	assert_near(it.pull_out, 0.0)
	assert_true(not it.to_dict().has("pull"), "没动过的货不写 pull 字段")


func test_split_pull_deviation_is_distance_weighted() -> void:
	# 一段好手法拉了 40%，一段坏手法拉了 10%：平均偏差靠近好手法
	var d := (0.1 * 0.4 + 3.0 * 0.1) / 0.5
	assert_near(PullPhysics.deviation_from_input({"d": d}), 0.68)
