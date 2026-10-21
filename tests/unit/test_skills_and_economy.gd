extends TestCase


func test_stall_phase_caps() -> void:
	var p := PlayerState.new()
	p.xp_pool = 100000.0
	var flags := {"shop_opened": false}
	for i in 10:
		SkillSystem.invest(p, "eloquence", 10000.0, flags)
	assert_eq(p.skill_level("eloquence"), 3, "摆摊阶段口才上限 3")
	assert_eq(SkillSystem.lock_reason(p, "eloquence", flags), "开店后解锁")
	assert_eq(SkillSystem.invest(p, "driving", 100.0, flags), 0.0, "驾驶摆摊阶段锁定")


func test_partial_investment() -> void:
	var p := PlayerState.new()
	p.xp_pool = 60.0
	SkillSystem.invest(p, "shout", 30.0, {})
	assert_eq(p.skill_level("shout"), 0)
	assert_near(float(p.skills["shout"]["invested"]), 30.0)
	SkillSystem.invest(p, "shout", 30.0, {})
	assert_eq(p.skill_level("shout"), 1, "60 点点亮 Lv1")
	assert_near(p.xp_pool, 0.0, 0.0001, "多余经验不应被吞")


func test_prerequisites() -> void:
	var p := PlayerState.new()
	p.phase = "shop"
	p.xp_pool = 100000.0
	p.skills["math"] = {"level": 2, "invested": 0.0}
	assert_true(SkillSystem.lock_reason(p, "math", {"shop_opened": true}).begins_with("需要"), "数学 Lv3 需要审美或客人观察 ≥1")
	p.skills["aesthetics"] = {"level": 1, "invested": 0.0}
	assert_eq(SkillSystem.lock_reason(p, "math", {"shop_opened": true}), "")


func test_season_material_blends_at_boundary() -> void:
	var mid := EconomyState.season_material(5)
	var edge := EconomyState.season_material(9)
	var next := EconomyState.season_material(10)
	assert_true(float(mid["ice_silk"]) < float(edge["ice_silk"]), "春末冰丝偏好开始上升")
	assert_true(float(edge["ice_silk"]) < float(next["ice_silk"]))


func test_continuous_cycle_decays() -> void:
	var e := EconomyState.new()
	for i in 10:
		e.push_observation({"price_ratio": 0.0, "sales": 10, "traffic": 100})
	for i in 4:
		e.push_observation({"price_ratio": 0.3, "sales": 15, "traffic": 150})
	var c1 := e.continuous_term()
	assert_true(c1 > 0.0, "最近比过去好，C 为正")
	for i in 40:
		e.push_observation({"price_ratio": 0.0, "sales": 10, "traffic": 100})
	assert_true(absf(e.continuous_term()) < absf(c1) * 0.2, "旧观测出了 36 旬窗口就不再有影响")


func test_year_end_only_reads_delta_history() -> void:
	var e1 := EconomyState.new()
	var e2 := EconomyState.new()
	e2.push_observation({"price_ratio": 5.0})
	var d1 := e1.year_end_step(GameRng.new(7))
	var d2 := e2.year_end_step(GameRng.new(7))
	assert_near(float(d1["consumption_level"]), float(d2["consumption_level"]), 0.0000001, "Base 不读旬级观测")
