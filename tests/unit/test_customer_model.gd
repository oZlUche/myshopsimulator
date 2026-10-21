extends TestCase
## 06 客人行为与议价中不依赖性格表示的部分：属性距离、热闹程度、合拍客人保底。


func test_color_distance_is_symmetric_and_bounded() -> void:
	var cs: Dictionary = DataDB.attributes()["colors"]
	for a in cs:
		assert_near(AttrDistance.color(a, a), 0.0)
		for b in cs:
			var d := AttrDistance.color(a, b)
			assert_true(d >= 0.0 and d <= 1.0, "%s-%s %f" % [a, b, d])
			assert_near(d, AttrDistance.color(b, a))
	assert_true(AttrDistance.color("red", "camel") < AttrDistance.color("red", "navy"), "红和驼比红和藏青近")
	assert_true(AttrDistance.color("black", "navy") < AttrDistance.color("black", "beige"), "深色之间近")


func test_pattern_and_material_similarity() -> void:
	assert_near(AttrDistance.pattern("plaid", "plaid"), 0.0)
	assert_near(AttrDistance.pattern_similarity("stripe", "plaid"), AttrDistance.pattern_similarity("plaid", "stripe"))
	assert_true(AttrDistance.pattern("plaid", "stripe") < AttrDistance.pattern("plaid", "floral"))
	assert_true(AttrDistance.material("wool", "cashmere") < AttrDistance.material("wool", "chiffon"))
	assert_near(AttrDistance.material("silk", "knit"), 1.0, 0.0001, "没列出的组合完全不像")


func test_expectation_distance_and_initial_p() -> void:
	var e := {"color": "red", "material": "wool", "pattern": "solid", "weight": {"color": 0.5, "material": 0.3, "pattern": 0.2}}
	assert_near(AttrDistance.to_expectation("scarf_solid_red_wool", e), 0.0)
	var near := AttrDistance.to_expectation("scarf_solid_camel_cashmere", e)
	var far := AttrDistance.to_expectation("scarf_floral_navy_chiffon", e)
	assert_true(near < far, "%f < %f" % [near, far])
	assert_near(AttrDistance.initial_p(0.0, 0.4), 0.9)
	assert_near(AttrDistance.initial_p(0.4, 0.4), 0.25)
	assert_true(AttrDistance.initial_p(0.1, 0.4) > AttrDistance.initial_p(0.3, 0.4))


func test_peek_confusion_follows_similarity_table() -> void:
	var s := GameState.new_game(3)
	var rates := {}
	for p in ["solid", "plaid", "floral"]:
		var item := s.inventory.create_item("scarf_%s_red_wool" % p)
		var wrong := 0
		var stripe := 0
		for i in 4000:
			var g: String = Sampler.peek(item, s.rng)["sku_guess"]
			if g != item.sku_id:
				wrong += 1
				assert_true(g.ends_with("_red_wool"), "只会认错图案：%s" % g)
				if g.begins_with("scarf_stripe"):
					stripe += 1
		rates[p] = wrong / 4000.0
		if p == "plaid":
			assert_true(stripe > wrong * 0.6, "格纹最常被认成条纹")
	assert_true(rates["solid"] < 0.05, "纯色几乎不认错 %f" % rates["solid"])
	assert_true(rates["plaid"] > 0.08 and rates["plaid"] < 0.25, "图案款容易认错 %f" % rates["plaid"])
	assert_true(rates["floral"] > 0.05, str(rates["floral"]))


func test_crowd_curve_endpoints() -> void:
	assert_near(StallSession.m_crowd(1.0, 0.1), 0.1)
	assert_near(StallSession.m_crowd(1.0, 1.0), 1.0)
	assert_near(StallSession.m_crowd(-1.0, 0.1), 1.0)
	assert_near(StallSession.m_crowd(-1.0, 1.0), 0.1)
	assert_near(StallSession.m_crowd(0.0, 0.3), 0.55)
	assert_near(StallSession.m_crowd(0.0, 0.9), 0.55)


func _session() -> StallSession:
	var s := GameState.new_game(9)
	PeriodRunner.begin_period(s)
	var x := 0.5
	while not s.street.can_place(x):
		x += 0.5
	return StallSession.new(s, x)


func test_heat_grows_with_visitors_and_goods() -> void:
	var ss := _session()
	assert_near(ss.heat(), 0.1, 0.0001, "空摊")
	var t: Slot = ss.s.inventory.slots_of_type("StallTable")[0]
	for i in 3:
		ss.api.place_on_top(ss.s.inventory.create_item("scarf_solid_red_wool"), t.id)
	assert_near(ss.heat(), 0.19)
	ss.visitors.append({"customer": CustomerProfile.new(), "state": "browsing"})
	ss.visitors.append({"customer": CustomerProfile.new(), "state": "browsing"})
	assert_near(ss.heat(), 0.79)
	ss.visitors.append({"customer": CustomerProfile.new(), "state": "browsing"})
	assert_near(ss.heat(), 1.0, 0.0001, "封顶 1")


func test_fit_timer_targets_goods_on_table() -> void:
	var ss := _session()
	var t0 := ss.fit_interval()
	assert_near(t0, StallSession.FIT_T0)
	var tables := ss.s.inventory.slots_of_type("StallTable")
	for sl in tables:
		while not sl.stack.is_full():
			ss.api.place_on_top(ss.s.inventory.create_item("scarf_plaid_purple_silk"), sl.id)
	assert_true(ss.fit_interval() < t0, "货越多保底越快")
	# 到点后下一位过路客的喜好正好对准摊上的货
	ss._fit_pending = true
	var seen := []
	ss.visitor_arrived.connect(func(v): seen.append(v))
	var guard := 0
	while ss._fit_pending and guard < 1000:
		ss._passerby()
		guard += 1
	assert_true(not ss._fit_pending)
	if not seen.is_empty():
		assert_near(seen[0]["customer"].match_score("scarf_plaid_purple_silk"), 1.0)


func test_settlement_stat_slots_exist() -> void:
	var s := GameState.new_game(1)
	for k in ["no_match", "scared_off", "lost_after_deal"]:
		assert_true(s.period_stats.has(k), k)
	var rep := PeriodRunner.end_period(s)
	for k in ["no_match", "scared_off", "lost_after_deal"]:
		assert_eq(int(rep[k]), 0)
