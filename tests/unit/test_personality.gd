extends TestCase
## 客人性格方案 C（06 §1.4）与新讲价流程（06 §3）：映射表、原型倾向、老存档迁移、按次数的耐心、真话与吹嘘。

const RED := "scarf_solid_red_wool"


func _vec(sociable: float, shrewd: float, composed: float, fastidious: float, agreeable: float) -> Dictionary:
	return {"sociable": sociable, "shrewd": shrewd, "composed": composed, "fastidious": fastidious, "agreeable": agreeable}


func _customer(vec: Dictionary) -> CustomerProfile:
	var c := CustomerProfile.new()
	c.id = "cu_test"
	c.personality = vec
	c.derived = Personality.derive(vec)
	c.preference = {"color": "red", "pattern": "solid", "material": "wool"}
	return c


func test_derive_is_deterministic_and_clamped() -> void:
	var mid := _vec(0.5, 0.5, 0.5, 0.5, 0.5)
	assert_eq(Personality.derive(mid), Personality.derive(mid), "不给 rng 时结果确定")
	var rng := GameRng.new(11)
	for i in 300:
		var v := _vec(rng.randf(), rng.randf(), rng.randf(), rng.randf(), rng.randf())
		var d := Personality.derive(v, rng)
		var pn := float(d["patience_n"])
		assert_true(pn >= 3.0 and pn <= 9.0 and pn == roundf(pn), "耐心次数是 3..9 的整数：%f" % pn)
		var ne := float(d["n_expect"])
		assert_true(ne >= 1.0 and ne <= 3.0 and ne == roundf(ne), "预期值 1..3 条：%f" % ne)
		assert_true(float(d["tolerance"]) >= 0.1 and float(d["tolerance"]) <= 0.6)
		for k in ["crowd_pref"]:
			assert_true(float(d[k]) >= -1.0 and float(d[k]) <= 1.0, k)
		assert_true(CustomerProfile.STRATEGIES.has(d["haggle_strategy"]))
	assert_true(float(Personality.derive(_vec(0.5, 0.5, 1.0, 0.5, 1.0))["patience_n"]) > float(Personality.derive(_vec(0.5, 0.5, 0.0, 0.5, 0.0))["patience_n"]), "从容随和的更能磨")
	assert_true(float(Personality.derive(_vec(0.5, 0.5, 0.5, 1.0, 0.5))["tolerance"]) < float(Personality.derive(_vec(0.5, 0.5, 0.5, 0.0, 0.5))["tolerance"]), "挑剔的容差小")


func test_archetypes_lean_their_way() -> void:
	var rng := GameRng.new(4)
	var econ := {"consumption_level": 1.0, "material_pref": {"wool": 1.0}}
	var trend := {"color": {"red": 1.0, "navy": 1.0}, "pattern": {"solid": 1.0, "plaid": 1.0}}
	var stats := {}
	for a in ["shrewd_auntie", "easygoing_guy", "leisurely_elder"]:
		var shrewd := 0.0
		var patience := 0.0
		var direct := 0
		for i in 300:
			var c := CustomerProfile.generate("cu_%d" % i, econ, trend, rng, a)
			assert_eq(c.archetype, a)
			assert_eq(c.expectations.size(), int(c.derived["n_expect"]))
			shrewd += c.trait_of("shrewd")
			patience += c.patience_n
			if c.haggle_strategy == "direct_discount":
				direct += 1
		stats[a] = {"shrewd": shrewd / 300.0, "patience": patience / 300.0, "direct": direct}
	assert_true(stats["shrewd_auntie"]["shrewd"] > stats["easygoing_guy"]["shrewd"] + 0.4, str(stats))
	assert_true(stats["shrewd_auntie"]["direct"] > stats["easygoing_guy"]["direct"] * 3, "精明大妈多半直接砍价：%s" % str(stats))
	assert_true(stats["leisurely_elder"]["patience"] > stats["shrewd_auntie"]["patience"], "闲逛老人更能磨：%s" % str(stats))


func test_describe_picks_the_strongest_traits() -> void:
	assert_eq(Personality.describe(_vec(0.5, 0.5, 0.5, 0.5, 0.5)), [], "平平无奇的人说不出特点")
	var w := Personality.describe(_vec(0.95, 0.5, 0.5, 0.1, 0.4))
	assert_eq(w, ["爱热闹", "不挑"])
	assert_true(Personality.describe(_vec(0.0, 1.0, 0.0, 1.0, 0.0)).size() <= 3, "最多说三个词")


func test_v1_regular_migrates_to_personality() -> void:
	var r := SaveManager.new().load_game("res://tests/save_fixtures/v0001.json")
	assert_true(r["ok"], str(r.get("error", "")))
	var s: GameState = r["state"]
	var c: CustomerProfile = s.customers.regulars["cu_000030"]
	assert_near(c.trait_of("agreeable"), 0.204557731747627, 0.0001, "kindness → 随和")
	assert_near(c.trait_of("composed"), (0.51043438911438 - 0.2) / 0.8, 0.0001, "patience → 从容")
	assert_near(c.trait_of("shrewd"), 0.55, 0.0001, "fake_leave → 精算 0.55")
	assert_eq(c.haggle_strategy, "fake_leave", "老档的讲价方式原样保留")
	assert_near(c.intent, 0.921363115310669, 0.0001)
	assert_true(c.archetype != "")
	assert_true(c.patience_n >= 3 and c.patience_n <= 9)
	assert_eq(c.preference, {"color": "grey", "material": "cashmere", "pattern": "floral"})
	assert_true(c.expectations[0].has("weight"))


func test_patience_counts_attempts_and_lv5_saves_one() -> void:
	var c := _customer(_vec(0.5, 0.5, 0.5, 0.5, 0.5))
	c.patience_n = 3
	var rng := GameRng.new(1)
	var h := HaggleState.start(c, RED, 50.0)
	for i in 3:
		assert_true(h._player_action(rng))
	assert_eq(h.patience_left, 0)
	assert_true(not h._player_action(rng), "磨光了他就走")
	assert_eq(h.result, "walked_away")
	assert_true(h.ran_out)
	var h5 := HaggleState.start(c, RED, 50.0, {}, {"free_every": 3})
	for i in 3:
		h5._player_action(rng)
	assert_eq(h5.patience_left, 1, "口才 Lv5：每第三次不扣耐心")


func test_first_quote_far_too_high_scares_him_off() -> void:
	var s := GameState.new_game(5)
	PeriodRunner.begin_period(s)
	var x := 0.5
	while not s.street.can_place(x):
		x += 0.5
	var ss := StallSession.new(s, x)
	var c := _customer(_vec(0.5, 0.5, 0.5, 0.5, 0.5))
	var other := {"customer": _customer(_vec(0.5, 0.5, 0.5, 0.5, 0.5)), "p_adj": 0.0, "state": "browsing"}
	var v := {"customer": c, "ctx": VisitContext.create(c), "item_id": "", "state": "asking", "wait": 30.0,
		"pick": {}, "initiative": false, "p_adj": 0.0, "p_final": 0.0, "want": [], "hint": "", "seen": {}}
	ss.visitors.append(v)
	ss.visitors.append(other)
	var h := HaggleState.start(c, RED, 200.0, {}, {}, v["ctx"], GameRng.new(2))
	h.offer_price(h.reserve * 4.0, GameRng.new(2))
	assert_eq(h.result, "scared_off")
	ss.finish(v, h)
	assert_eq(int(s.period_stats.get("scared_off", 0)), 1)
	assert_true(not ss.visitors.has(v))
	# 磨光耐心、脾气爆的客人嘟囔一句，旁边的人也听见了
	var g := HaggleState.start(c, RED, 50.0, {}, {}, null, null)
	g.grumbled = true
	g.result = "walked_away"
	ss.visitors.append(v)
	ss.finish(v, g)
	assert_near(float(other["p_adj"]), -0.05)


func test_true_claims_land_more_often_than_bluffs() -> void:
	var c := _customer(_vec(0.5, 0.5, 0.5, 0.5, 0.5))
	c.patience_n = 9
	var rng := GameRng.new(8)
	var honest := 0
	var bluff := 0
	for i in 2000:
		# 真货正合他意，他却看成了藏青：说颜色是真话
		var h := HaggleState.start(c, RED, 1000.0, {"perceived_sku": "scarf_solid_navy_wool"})
		h.use_strategy("color", rng)
		if h.adj >= 0.0:   # 没被扣分 = 说服成功（台词随后会被他的还价盖掉）
			honest += 1
			assert_near(float(h.d_dims["color"]), 0.0, 0.0001, "说中了就按真货算")
		# 真货是藏青，他却看成了红：说颜色是吹嘘
		var b := HaggleState.start(c, "scarf_solid_navy_wool", 1000.0, {"perceived_sku": RED})
		b.use_strategy("color", rng)
		if b.adj >= 0.0:
			bluff += 1
	assert_true(honest > 1100 and honest < 1500, "真话成功率约 0.65：%d" % honest)
	assert_true(bluff > 150 and bluff < 450, "吹嘘成功率约 0.15：%d" % bluff)
