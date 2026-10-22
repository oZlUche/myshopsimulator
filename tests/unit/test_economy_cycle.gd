extends TestCase
## 经济周期与价格体系（09 阶段 0）：物价 π、材质供给冲击 M_m、本地店进货价、客人预算、客流、购物意向。


func _steps(e: EconomyState, n: int, g: float, seed_value: int) -> void:
	var rng := GameRng.new(seed_value)
	for p in range(2, n + 2):
		e.period_step(p, g, rng)


func test_price_level_grows_about_3pct_a_year() -> void:
	var e := EconomyState.new()
	_steps(e, 36, 0.0, 1)
	assert_true(e.price_level > 1.02 and e.price_level < 1.04, "中性景气一年约 +3%%，实际 %f" % e.price_level)


func test_inflation_follows_boom_and_bust() -> void:
	var boom := EconomyState.new()
	var flat := EconomyState.new()
	var bust := EconomyState.new()
	_steps(boom, 36, 0.2, 3)
	_steps(flat, 36, 0.0, 3)
	_steps(bust, 36, -0.2, 3)
	assert_true(boom.price_level > flat.price_level and flat.price_level > bust.price_level, "景气高通胀高（菲利普斯曲线）")
	assert_true(boom.price_level > 1.05 and boom.price_level < 1.07, "景气 1.2 年化约 5.9%%，实际 %f" % boom.price_level)
	assert_true(bust.price_level > 0.99 and bust.price_level < 1.01, "景气 0.8 年化约 0%%，实际 %f" % bust.price_level)


func test_material_shock_mean_reverts_and_stays_bounded() -> void:
	var e := EconomyState.new()
	e.material_shock["wool"] = 1.5
	_steps(e, 30, 0.0, 5)
	assert_true(absf(float(e.material_shock["wool"]) - 1.0) < 0.2, "冲击会回到 1 附近")
	var rng := GameRng.new(9)
	var sum := 0.0
	var n := 0
	for p in range(2, 600):
		e.period_step(p, 0.0, rng)
		for m in e.material_shock:
			var v := e.material_mult(m, p)
			assert_true(v >= EconomyState.SHOCK_MIN and v <= EconomyState.SHOCK_MAX, "M_m 在 [0.7, 1.5] 里")
			sum += v
			n += 1
	assert_near(sum / n, 1.0, 0.03, "长期均值在 1 附近")


func test_material_event_jumps_then_decays() -> void:
	var e := EconomyState.new()
	e.material_events = [{"material": "cashmere", "boost": 0.15, "start": 10, "duration": 6}]
	assert_near(e.material_mult("cashmere", 9), 1.0, 0.0001, "事件开始前不生效")
	assert_near(e.material_mult("cashmere", 10), 1.15, 0.0001, "当旬跳 +0.15")
	assert_near(e.material_mult("cashmere", 13), 1.075, 0.0001, "6 旬内线性衰减")
	assert_near(e.material_mult("cashmere", 16), 1.0, 0.0001)
	assert_near(e.material_mult("wool", 10), 1.0, 0.0001, "只影响那一种材质")
	e.period_step(17, 0.0, GameRng.new(1))
	for ev in e.material_events:
		assert_true(int(ev["start"]) != 10, "过期事件被清掉")


func test_supplier_price_carries_pi_and_material_mult() -> void:
	var econ := EconomyState.new().effective(1)
	var mult: Dictionary = econ["material_cost_mult"]
	for m in mult:
		mult[m] = 1.0
	var cat1 := LocalSupplier.refresh_catalog(econ, GameRng.new(42))
	econ["price_level"] = 2.0
	for m in mult:
		mult[m] = 1.5
	var cat2 := LocalSupplier.refresh_catalog(econ, GameRng.new(42))
	assert_eq(cat1.size(), cat2.size())
	for i in cat1.size():
		assert_eq(cat1[i]["sku_id"], cat2[i]["sku_id"], "同一个种子挑的货一样")
		var cost := float(DataDB.sku(cat2[i]["sku_id"])["base_cost"]) * 3.0
		var price := float(cat2[i]["unit_price"])
		assert_true(price >= cost * 1.05 - 0.25 and price <= cost * 1.3 + 0.25, "进货价 = base_cost·π·M·U(1.05,1.3)")
		assert_near(price / float(cat1[i]["unit_price"]), 3.0, 0.15)


func test_season_pressure_and_demand_pull_in_cost_mult() -> void:
	var e := EconomyState.new()
	var winter := e.effective(28)
	var mult: Dictionary = winter["material_cost_mult"]
	assert_true(float(mult["cashmere"]) > 1.0 and float(mult["ice_silk"]) < 1.0, "冬天羊绒贵、冰丝便宜")
	for m in mult:
		assert_true(float(mult[m]) >= 0.9 - 0.0001 and float(mult[m]) <= 1.08 + 0.0001, "S_mat 夹在 [0.9, 1.08]")
	e.base["consumption_level"] = 1.2
	var hot: Dictionary = e.effective(28)["material_cost_mult"]
	assert_near(float(hot["wool"]) / float(mult["wool"]), 1.05, 0.0001, "景气 1.2 → 进货价 +5%")


func test_effective_reports_doc09_fields() -> void:
	var e := EconomyState.new()
	var econ := e.effective(1)
	for k in ["G", "price_level", "interest_rate", "freight_index", "material_cost_mult", "credit_risk", "spending_power", "rent_index_target"]:
		assert_true(econ.has(k), "effective() 有 %s" % k)
	assert_near(float(econ["G"]), 1.0, 0.0001)
	assert_near(float(econ["interest_rate"]), 0.05 + 0.5 * (pow(1.0008, 36) - 1.0 - 0.03), 0.0001)
	e.base["consumption_level"] = 0.8
	var bust := e.effective(1)
	assert_near(float(bust["credit_risk"]), 0.13, 0.0001, "衰退拖账 +30%")
	assert_near(float(bust["spending_power"]), pow(0.8, 1.2), 0.0001)
	assert_true(float(bust["interest_rate"]) < float(econ["interest_rate"]), "衰退降息")
	assert_true(float(e.effective(28)["freight_index"]) > float(e.effective(10)["freight_index"]), "冬天运力紧")
	e.base["consumption_level"] = 0.1
	assert_near(e.level(), EconomyState.G_MIN, 0.0001, "G 夹在 [0.6, 1.6]")


func test_customer_budget_and_intent_follow_economy() -> void:
	var trend := {"color": {"red": 1.0}, "pattern": {"solid": 1.0}}
	var flat := {"consumption_level": 1.0, "material_pref": {"wool": 1.0}}
	var bust := {"G": 0.8, "consumption_level": 0.8, "spending_power": pow(0.8, 1.2), "price_level": 1.1, "material_pref": {"wool": 1.0}}
	var a := CustomerProfile.generate("a", flat, trend, GameRng.new(7))
	var b := CustomerProfile.generate("b", bust, trend, GameRng.new(7))
	assert_near(b.budget_mult / a.budget_mult, pow(0.8, 1.2) * 1.1, 0.0001, "budget_mult = G^1.2 · π · 噪声")
	assert_near(b.intent, clampf(float(b.derived["intent"]) - 0.02, 0.05, 1.0), 0.0001, "购物意向 + 0.1·g")
	assert_near(a.intent, float(a.derived["intent"]), 0.0001)


func test_regular_budget_is_recomputed_on_return() -> void:
	var c := CustomerProfile.generate("c", {"consumption_level": 1.0, "material_pref": {"wool": 1.0}},
		{"color": {"red": 1.0}, "pattern": {"solid": 1.0}}, GameRng.new(3))
	var noise := c.budget_noise
	c.apply_economy({"G": 1.0, "price_level": 1.5})
	assert_near(c.budget_mult, noise * 1.5, 0.0001, "几年后回来，预算跟着物价涨")
	var d := c.to_dict()
	d.erase("budget_noise")
	var old := CustomerProfile.from_dict(d)
	assert_near(old.budget_noise, old.budget_mult, 0.0001, "老存档的预算倍率当个人噪声用")


func test_traffic_follows_G() -> void:
	var s := GameState.new_game(5)
	PeriodRunner.begin_period(s)
	s.economy.base["consumption_level"] = 0.8
	var x := 0.5
	while not s.street.can_place(x):
		x += 0.5
	var ss := StallSession.new(s, x)
	var b := float(s.econ_now()["rhythm_mult"])
	assert_near(ss._traffic_mult, 0.94 * b, 0.0001, "过路客 × (0.7 + 0.3·G) · B")


func test_end_period_moves_price_level_and_list_price() -> void:
	var s := GameState.new_game(11)
	PeriodRunner.begin_period(s)
	PeriodRunner.end_period(s)
	assert_true(s.economy.price_level > 0.999 and s.economy.price_level < 1.004, "一旬通胀在夹值范围里")
	assert_eq(s.economy.g_history.size(), 1)
	var sku: String = DataDB.skus().keys()[0]
	s.economy.price_level = 1.2
	assert_near(s.list_price(sku), snappedf(float(DataDB.sku(sku)["base_price"]) * 1.2, 1.0), 0.0001, "默认标价 = base_price × π")


func test_price_ratio_observation_is_deflated() -> void:
	var s := GameState.new_game(2)
	s.economy.price_level = 1.5
	var sku: String = DataDB.skus().keys()[0]
	var it := s.inventory.create_item(sku)
	var c := CustomerProfile.new()
	c.id = "x"
	ActionAPI.new(s).sell_item(it, float(DataDB.sku(sku)["base_price"]) * 1.5, c, 10.0)
	assert_near(float(s.period_stats["price_ratio_sum"]), 1.0, 0.0001, "按标准价卖，成交价比 = 1（不因通胀推高景气）")


func test_economy_roundtrip_and_old_save_defaults() -> void:
	var e := EconomyState.new()
	_steps(e, 40, 0.1, 8)
	e.material_events = [{"material": "silk", "boost": -0.15, "start": 40, "duration": 6}]
	var back := EconomyState.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert_near(back.price_level, e.price_level, 0.000001)
	assert_near(back.material_mult("silk", 41), e.material_mult("silk", 41), 0.000001)
	assert_near(back.rent_index_target, e.rent_index_target, 0.000001)
	assert_eq(back.g_history.size(), EconomyState.RENT_WINDOW)
	var old := EconomyState.from_dict({"base": {"consumption_level": 1.1}})
	assert_near(old.price_level, 1.0, 0.0001, "老存档 π 从 1 起步")
	assert_near(old.material_mult("wool", 5), 1.0, 0.0001, "老存档 M 从 1 起步")
	assert_near(old.fuel_index_rw, 1.0, 0.0001)
	assert_true(old.policy.has("tax_sales_rate"), "税制参数有默认值")


func test_wholesale_and_equipment_prices_carry_pi() -> void:
	var econ := {"price_level": 2.0, "material_cost_mult": {"chiffon": 1.0}}
	assert_near(Wholesale.unit_cost("dot", "chiffon", "single", econ), snappedf(Wholesale.unit_cost("dot", "chiffon", "single") * 2.0, 0.5), 0.51,
		"批发厂价也乘 π")
	var s := GameState.new_game(1)
	s.economy.price_level = 1.5
	var def_id: String = DataDB.equipment().keys()[0]
	assert_near(s.equipment_price(def_id), snappedf(float(DataDB.equipment()[def_id].get("price", 0.0)) * 1.5, 1.0), 0.0001, "设备价乘 π")


func test_continuous_term_is_decentered() -> void:
	var e := EconomyState.new()
	for i in 4:
		e.push_observation({"price_ratio": 0.0, "sales": 10, "traffic": 500})
	for i in 5:
		e.push_observation({"price_ratio": 0.5, "sales": 30, "traffic": 900})
	assert_near(e.continuous_term(), 0.0, 0.0001, "开局前 10 旬（基线不足 4 旬）C = 0")
	e.push_observation({"price_ratio": 0.5, "sales": 30, "traffic": 900})
	assert_true(e.continuous_term() > 0.0, "第 10 旬起基线够 4 旬，C 开始起作用")
	var cheap := EconomyState.new()
	for i in 30:
		cheap.push_observation({"price_ratio": -0.25, "sales": 8, "traffic": 500})
	assert_near(cheap.continuous_term(), 0.0, 0.0001, "一贯卖得便宜不会拉低景气")
	var boom := EconomyState.new()
	for i in 30:
		boom.push_observation({"price_ratio": -0.1, "sales": 10, "traffic": 500})
	for i in 6:
		boom.push_observation({"price_ratio": 0.0, "sales": 13, "traffic": 650})
	var c := boom.continuous_term()
	assert_true(c > 0.09 and c < 0.13, "30 旬平稳后连续 6 旬三维各高 1 个显著单位：C ≈ +0.11，实际 %f" % c)
	for i in 36:
		boom.push_observation({"price_ratio": 0.0, "sales": 13, "traffic": 650})
	assert_near(boom.continuous_term(), 0.0, 0.0001, "好转持续满 36 旬，基线跟上，C 回零")
	var crash := EconomyState.new()
	for i in 30:
		crash.push_observation({"price_ratio": 0.0, "sales": 10, "traffic": 500})
	for i in 6:
		crash.push_observation({"price_ratio": -5.0, "sales": 0, "traffic": 0})
	assert_near(crash.continuous_term(), -EconomyState.C_MAX, 0.0001, "C 夹在 ±0.15")


func test_season_pressure_uses_share_over_mean() -> void:
	var e := EconomyState.new()
	var winter: Dictionary = e.effective(28)["material_cost_mult"]
	var share: Dictionary = e.effective(28)["material_pref"]
	var n := float(share.size())
	for m in winter:
		var expect := clampf(1.0 + 0.1 * (float(share.get(m, 0.0)) * n - 1.0), 0.9, 1.08)
		assert_near(float(winter[m]), expect, 0.0001, "S_mat = 1 + 0.1·(占比/平均占比 − 1)：%s" % m)
	assert_near(float(winter["cashmere"]), 1.08, 0.0001, "当季主材顶到 +8%")
	assert_true(float(winter["ice_silk"]) < 0.92, "反季材质接近 −10%")
	assert_eq(e.policy["income_bracket_limits"], [30000.0, 100000.0])
