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


func _table_with(s: GameState, api: ActionAPI, n: int) -> Slot:
	var table: Slot = s.inventory.slots_of_type("StallTable")[0]
	for i in n:
		api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), table.id)
	return table


func test_partial_pull_stays_out_and_above_keeps_shift() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table := _table_with(s, api, 3)
	var st := table.stack
	# 好手法拉到 30% 停手：货停在外面，上面两层被带歪，越往上越歪
	var r := api.pull_segment(table.id, 0, -0.3, 0.0, -0.3)
	if r["collapsed"]:
		return
	assert_near(st.items[0].pull_out, -0.3)
	assert_true(st.items[1].shift < 0.0 and st.items[2].shift < st.items[1].shift, "%f %f" % [st.items[1].shift, st.items[2].shift])
	# 存档读回来还在
	var back := ItemStack.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	assert_near(back.items[0].pull_out, -0.3)
	assert_near(back.items[2].shift, st.items[2].shift)
	# 抽出后剩下的货不往下沉、不归位：留出一层空隙，带歪的保持带歪
	var shift_top := st.items[2].shift
	var got := api.pull_item(table.id, 0, {"resolved": true})
	assert_true(got["item"] != null)
	assert_near(got["item"].pull_out, 0.0)
	assert_eq(st.height(), 2)
	assert_eq(st.items[0].gap_below, 1)
	assert_eq(st.layer_of(0), 1)
	assert_eq(st.layer_of(1), 2)
	assert_near(st.items[1].shift, shift_top)
	assert_eq(ItemStack.from_dict(JSON.parse_string(JSON.stringify(st.to_dict()))).layer_of(1), 2)
	# 放顶时压实，理货时归位
	api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), table.id)
	assert_eq(st.layer_of(2), 2)
	api.restack(table.id, st.items.map(func(it): return it.id))
	for it in st.items:
		assert_near(it.shift, 0.0)


func test_each_segment_rolls_its_own_collapse() -> void:
	# 每段单独判定：粗暴的一段可以在没抽出来之前就把上面弄塌，目标还露在原位
	var collapsed := false
	for attempt in 30:
		var s := _state()
		var api := ActionAPI.new(s)
		var table := _table_with(s, api, 3)
		var r := api.pull_segment(table.id, 0, 0.2, 4.0, 0.2)
		if r["collapsed"]:
			collapsed = true
			assert_eq(table.stack.height(), 1)
			assert_eq(table.stack.collapsed_pile.size(), 2)
			assert_near(table.stack.items[0].pull_out, 0.2)
			break
	assert_true(collapsed, "偏差很大的一段应该能弄塌")
	# 好手法的一段几乎不会塌
	var s2 := _state()
	var api2 := ActionAPI.new(s2)
	var t2 := _table_with(s2, api2, 3)
	assert_true(api2.pull_segment(t2.id, 0, 0.1, 0.0, 0.1)["p_collapse"] < 0.1)


func test_old_item_without_pull_fields_loads() -> void:
	var it := ScarfItem.from_dict({"id": "i1", "sku_id": "scarf_solid_red_wool"})
	assert_near(it.pull_out, 0.0)
	assert_eq(it.gap_below, 0)
	assert_true(not it.to_dict().has("pull"), "没动过的货不写 pull 字段")


func test_pull_never_gets_stuck() -> void:
	# 上面再重、手法再差，一直拖也一定能带出来（03 §2.0），只是慢
	var worst := PullPhysics.follow_ratio(20.0, 90.0, "center")
	assert_true(worst >= PullPhysics.MIN_FOLLOW, str(worst))
	assert_true(PullPhysics.follow_ratio(0.0, 40.0, "corner") > worst)


func test_collapse_risk_rewards_care() -> void:
	# 小心抽：上面压 6 份也基本不塌；糙手法：上面压 2 份就有明显风险
	var d_careful := PullPhysics.deviation_from_input(ActionAPI.CAREFUL_PULL)
	assert_true(PullPhysics.collapse_probability(d_careful, 6) < 0.06, str(PullPhysics.collapse_probability(d_careful, 6)))
	assert_true(PullPhysics.collapse_probability(1.5, 2) > 0.4, str(PullPhysics.collapse_probability(1.5, 2)))


func test_take_top_never_collapses_and_fills_hand() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table := _table_with(s, api, 3)
	var hand := s.inventory.hand()
	var top_id := table.stack.top().id
	var it := api.take_top_to_hand(table.id)
	assert_eq(it.id, top_id)
	api.take_top_to_hand(table.id)
	api.take_top_to_hand(table.id)
	assert_eq(table.stack.height(), 0)
	assert_eq(table.stack.collapsed_pile.size(), 0)
	assert_eq(hand.stack.height(), 3)
	# 手上满了就拿不了
	var t2: Slot = s.inventory.slots_of_type("StallTable")[1]
	api.place_on_top(s.inventory.create_item("scarf_solid_red_wool"), t2.id)
	assert_true(api.take_top_to_hand(t2.id) == null)
	# 收摊时手上的货也回到行囊
	var bag_before := s.inventory.count_items("", "Bag")
	assert_eq(api.pack_up(), 0)
	assert_eq(s.inventory.count_items("", "Bag"), bag_before + 4)
	assert_eq(hand.stack.height(), 0)


func test_npc_fetch_by_personality() -> void:
	var tops := 0
	var top_collapses := 0
	var pulls := 0
	for k in 20:
		var s := _state()
		s.rng = GameRng.new(1000 + k)
		var api := ActionAPI.new(s)
		var table := _table_with(s, api, 3)
		var target := table.stack.items[0]
		var r := api.npc_fetch(table.id, 0, {"patience": 0.95, "careless": 0.05, "first_visit": false})
		assert_eq(r["item"].id, target.id)
		if r["method"] == "top":
			tops += 1
			if r["collapsed"] or not table.stack.collapsed_pile.is_empty():
				top_collapses += 1
			# 上面那两份被随手放到别的摊位格堆顶
			assert_eq(table.stack.height(), 0)
			assert_true(r["seconds"] > ActionAPI.NPC_PULL_SECONDS)
		var s2 := _state()
		s2.rng = GameRng.new(2000 + k)
		var api2 := ActionAPI.new(s2)
		var t2 := _table_with(s2, api2, 3)
		if api2.npc_fetch(t2.id, 0, {"patience": 0.05, "careless": 0.95, "first_visit": true})["method"] == "pull":
			pulls += 1
	assert_true(tops >= 15, "谨慎的多数拆顶：%d" % tops)
	assert_eq(top_collapses, 0)
	assert_true(pulls >= 15, "马虎的多数直接抽：%d" % pulls)


## 一格摊位上依次摆 skus（自底向上），堆高放宽到 8。
func _table_of(s: GameState, api: ActionAPI, skus: Array) -> Slot:
	var table: Slot = s.inventory.slots_of_type("StallTable")[0]
	table.stack.max_height = 8
	for sku in skus:
		api.place_on_top(s.inventory.create_item(sku), table.id)
	return table


const _R := "scarf_solid_red_wool"
const _N := "scarf_solid_navy_wool"


func test_batch_take_top_stops_when_hand_is_full() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table := _table_of(s, api, [_R, _R, _N, _N, _R])
	var top := table.stack.top()
	var hand := s.inventory.hand()
	var last := api.take_top_to_hand(table.id, 5)
	assert_eq(hand.stack.height(), 3, "手上只能拿 3 份")
	assert_eq(table.stack.height(), 2)
	assert_eq(hand.stack.items[0].id, top.id, "一份份从顶上拿，最先拿的在手上最下面")
	assert_eq(last.id, hand.stack.top().id)
	assert_eq(api.hand_room(), 0)
	assert_true(api.take_top_to_hand(table.id, 2) == null, "手满了一份都拿不了")


func test_pull_block_keeps_order_and_leaves_gap() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table := _table_of(s, api, [_R, _N, _R, _N, _R])
	var st := table.stack
	var ids := st.items.map(func(it): return it.id)
	var hand := s.inventory.hand()
	assert_true(api.pull_block(table.id, 1, 4, {"resolved": true})["item"] == null, "4 份的块比手上余量 3 大，不能开始")
	assert_eq(st.height(), 5, "没开始就不动")
	var r := api.pull_block(table.id, 1, 2, {"resolved": true})
	assert_eq(r["items"].size(), 2)
	assert_eq(hand.stack.items.map(func(it): return it.id), [ids[1], ids[2]], "按原顺序进手上")
	assert_eq(st.items.map(func(it): return it.id), [ids[0], ids[3], ids[4]])
	assert_eq(st.items[1].gap_below, 2, "下面空出两层")
	assert_eq(st.layer_of(2), 4)
	# 手上余量 1：只能再抽 1 份的块
	assert_true(api.pull_block(table.id, 0, 1, {"resolved": true})["item"] == null)


func test_block_is_heavier_and_riskier() -> void:
	assert_near(PullPhysics.block_kw_mult(1), 1.0)
	assert_near(PullPhysics.block_kw_mult(3), 1.5)
	assert_near(PullPhysics.block_alpha_mult(3), 1.4)
	assert_true(PullPhysics.follow_ratio(3.0, 40.0, "corner", PullPhysics.block_kw_mult(3)) < PullPhysics.follow_ratio(3.0, 40.0, "corner"), "块越厚越沉")
	assert_true(PullPhysics.collapse_probability(0.8, 2, PullPhysics.block_alpha_mult(3)) > PullPhysics.collapse_probability(0.8, 2), "块越厚越容易塌")
	# 小游戏一段：整块一起出来，只有块上面的会被带歪 / 会塌
	var s := _state()
	var api := ActionAPI.new(s)
	var table := _table_of(s, api, [_R, _N, _R, _N, _R])
	var st := table.stack
	var r := api.pull_segment(table.id, 1, 0.2, 0.3, 0.2, 2)
	assert_near(float(r["p_collapse"]), PullPhysics.collapse_probability(0.3, 2, 1.2), 0.0001, "按块上面 2 份、α ×1.2 判定")
	if not r["collapsed"]:
		assert_near(st.items[1].pull_out, 0.2)
		assert_near(st.items[2].pull_out, 0.2, 0.0001, "块里的每份一起出来")
		assert_near(st.items[0].pull_out, 0.0)
		assert_true(st.items[4].shift > st.items[3].shift and st.items[3].shift > 0.0, "块上面的越往上越歪")


func test_peek_range_and_place_from_carrier() -> void:
	var s := _state()
	var api := ActionAPI.new(s)
	var table := _table_of(s, api, [_R, _N, _R])
	assert_eq(api.peek_range(table.id, 0, 2).size(), 3, "批量翻看逐份看")
	for it in table.stack.items:
		assert_true(s.knowledge.perceived.has(it.id))
	var hand := s.inventory.hand()
	api.take_top_to_hand(table.id, 3)
	var order := hand.stack.items.map(func(it): return it.id)
	var other: Slot = s.inventory.slots_of_type("StallTable")[1]
	other.stack.max_height = 2
	assert_eq(api.place_from_carrier(other.id, 3, 0), 2, "放不下的留在手上")
	assert_eq(other.stack.items.map(func(it): return it.id), [order[0], order[1]], "按原顺序放上去")
	assert_eq(hand.stack.items.map(func(it): return it.id), [order[2]])
	var third: Slot = s.inventory.slots_of_type("StallTable")[2]
	assert_eq(api.place_from_carrier(third.id, 1), 1, "lo < 0：放手上最上面那份")
	assert_eq(hand.stack.height(), 0)

