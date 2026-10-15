extends TestCase


func test_vendor_exclusion_radius() -> void:
	var st := Street.new()
	st.vendors = [{"id": "v", "x": 10.0, "radius": 3.0}]
	assert_true(not st.can_place(11.0))
	assert_true(st.can_place(14.0))


func test_full_stall_period_runs_and_sells() -> void:
	var s := GameState.new_game(7)
	PeriodRunner.begin_period(s)
	AutoSeller.auto_prepare(s)
	var rep := AutoSeller.simulate_stall_period(s)
	assert_eq(s.clock.period, 2)
	assert_true(int(rep["traffic"]) > 50, "一旬应有相当数量的过路客：%d" % int(rep["traffic"]))
	assert_true(int(rep["sales"]) > 0, "自动摆摊一旬应至少卖出一件")
	assert_eq(s.inventory.count_items("", "StallTable"), 0, "收摊后摊位应清空")


func test_year_of_play_is_stable() -> void:
	var s := GameState.new_game(11)
	for i in 36:
		PeriodRunner.begin_period(s)
		AutoSeller.auto_prepare(s, 0.5)
		AutoSeller.simulate_stall_period(s, -1.0, 2.0)
	assert_eq(s.clock.period, 37)
	assert_eq(s.economy.base_delta_history.size(), 1, "满一年应发生一次宏观调整")
	assert_true(s.player.cash > 0.0)


func test_regular_overcharge_lowers_return() -> void:
	var reg := CustomerRegistry.new()
	var c := CustomerProfile.new()
	c.id = "cu_x"
	c.loyalty_base = 0.5
	reg.record_purchase(c, 100.0, 100.0)
	var p0: float = reg.return_probability["cu_x"]
	reg.record_purchase(c, 150.0, 100.0)
	assert_true(reg.return_probability["cu_x"] < p0, "宰客降低回购率")


func test_haggle_never_sells_above_reserve_by_offer() -> void:
	var rng := GameRng.new(3)
	var c := CustomerProfile.generate("c", {"consumption_level": 1.0, "material_pref": {"wool": 1.0}}, {"color": {"red": 1.0}, "pattern": {"solid": 1.0}}, rng)
	var h := HaggleState.start(c, "scarf_solid_red_wool", 9999.0)
	for i in 10:
		h.offer_price(9999.0, rng)
	assert_eq(h.result, "walked_away", "远超心理价不应成交")
