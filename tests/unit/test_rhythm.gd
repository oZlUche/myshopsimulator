extends TestCase
## 节拍层 B(t)（09 §1.8）：季节需求、日历事件、突发天气只乘客流和购物意向，年均归一到 1。


func test_fixed_part_averages_one_over_a_year() -> void:
	var e := EconomyState.new()
	var sum := 0.0
	var peak_q := 0
	var low_q := 0
	for q in range(1, 37):
		var b := e.rhythm(q)
		assert_true(b >= EconomyState.B_MIN and b <= EconomyState.B_MAX, "B 在 [0.6, 1.6] 里")
		sum += b
		if peak_q == 0 or b > e.rhythm(peak_q):
			peak_q = q
		if low_q == 0 or b < e.rhythm(low_q):
			low_q = q
	assert_near(sum / 36.0, 1.0, 0.0001, "没天气时夹限后一年均值 = 1.000")
	assert_near(EconomyState.rhythm_norm(), 1.0994, 0.001, "Z 让夹限后的均值归一")
	assert_true(peak_q >= 34, "年关三旬是全年客流峰，实际峰在第 %d 旬" % peak_q)
	assert_near(e.rhythm(1 + 36), e.rhythm(1), 0.000001, "固定部分按年循环")
	var season_sum := 0.0
	for q in range(1, 37):
		season_sum += EconomyState.season_demand(q)
	assert_near(season_sum / 36.0, 1.0, 0.000001, "季节需求余弦年均恰为 1")
	assert_near(EconomyState.season_demand(32), 1.35, 0.000001, "11 月中峰 1.35")
	assert_near(EconomyState.season_demand(14), 0.65, 0.000001, "5 月中谷 0.65")
	assert_true(e.rhythm(14) < e.rhythm(32), "5 月中比 11 月中冷清")


func test_calendar_events_and_market_day() -> void:
	assert_eq(EconomyState.calendar_names(36), ["年关抢购", "集市日"], "年关最后一旬正好也是集市日")
	assert_eq(EconomyState.calendar_names(1), ["年初清淡"])
	assert_eq(EconomyState.calendar_names(4), ["开春集"])
	assert_eq(EconomyState.calendar_names(5), [], "平常旬没事件")
	assert_eq(EconomyState.calendar_names(36 + 4), ["开春集"], "第二年同一旬")
	var c := EconomyState.calendar(35)
	assert_near(float(c[0]), 1.45, 0.000001)
	assert_near(float(c[1]), 0.15, 0.000001)
	var cm := EconomyState.calendar(24)
	assert_near(float(cm[0]), 1.1 * 1.15, 0.000001, "丰收季碰上集市日，倍率相乘")
	var e := EconomyState.new()
	assert_near(e.rhythm_intent(36), 0.20, 0.000001, "年关意向 +0.20")
	assert_near(e.rhythm_intent(2), -0.05, 0.000001, "年初清淡意向 −0.05")
	var econ := e.effective(35)
	assert_eq(econ["calendar_events"], ["年关抢购"])
	assert_near(float(econ["rhythm_mult"]), e.rhythm(35), 0.000001)
	assert_near(float(econ["rhythm_intent_add"]), 0.15, 0.000001)


func test_weather_decays_and_indoor_rain_is_halved() -> void:
	var e := EconomyState.new()
	e.rhythm_events = [{"kind": "cold", "start": 30, "duration": 2, "traffic_mult": 1.3, "intent_add": 0.1}]
	assert_near(float(e.weather(29)[0]), 1.0, 0.000001, "开始前不生效")
	assert_near(float(e.weather(30)[0]), 1.3, 0.000001, "当旬 ×1.3")
	assert_near(float(e.weather(31)[0]), 1.15, 0.000001, "第二旬线性衰减一半")
	assert_near(float(e.weather(32)[0]), 1.0, 0.000001, "持续 2 旬后没了")
	assert_near(float(e.weather(30)[1]), 0.1, 0.000001)
	assert_eq(e.weather_names(30), ["突然降温"])
	assert_near(e.rhythm(30), clampf(e.rhythm(30 + 36) * 1.3, 0.6, 1.6), 0.000001, "天气乘在固定部分上")
	e.rhythm_events = [{"kind": "rain", "start": 12, "duration": 1, "traffic_mult": 0.75, "intent_add": 0.0}]
	assert_near(float(e.weather(12)[0]), 0.75, 0.000001, "街上 ×0.75")
	assert_near(float(e.weather(12, true)[0]), 0.875, 0.000001, "店里减半 ×0.875")
	assert_near(e.rhythm(12), EconomyState.B_MIN, 0.000001, "夏天本来就淡，下雨顶到 0.6 的夹限")
	# 倍率本身拿一个不碰夹限的旬看
	e.rhythm_events = [{"kind": "rain", "start": 30, "duration": 1, "traffic_mult": 0.75, "intent_add": 0.0}]
	var wet := e.effective(30)
	assert_near(float(wet["rhythm_mult"]), e.rhythm(30 + 36) * 0.75, 0.0001)
	assert_near(float(wet["rhythm_mult_indoor"]), e.rhythm(30 + 36) * 0.875, 0.0001)
	assert_eq(wet["weather_events"], ["连着下雨"])


func test_weather_rolls_in_season_without_stacking() -> void:
	var e := EconomyState.new()
	var rng := GameRng.new(4)
	var counts := {}
	var max_alive := 0
	for p in range(2, 36 * 40 + 2):
		e.period_step(p, 0.0, rng)
		var q := EconomyState.year_q(p)
		var kinds := {}
		for ev in e.rhythm_events:
			if int(ev["start"]) == p:
				counts[ev["kind"]] = int(counts.get(ev["kind"], 0)) + 1
				var ok := false
				for r in EconomyState.WEATHER[ev["kind"]]["q"]:
					ok = ok or (q >= int(r[0]) and q <= int(r[1]))
				assert_true(ok, "%s 只在季节里出现（第 %d 旬）" % [ev["kind"], q])
			if p - int(ev["start"]) < int(ev["duration"]):
				assert_true(not kinds.has(ev["kind"]), "同类不叠加")
				kinds[ev["kind"]] = true
		max_alive = maxi(max_alive, e.rhythm_events.size())
	assert_true(max_alive <= EconomyState.WEATHER.size(), "过期的天气会清掉")
	for k in EconomyState.WEATHER:
		assert_true(int(counts.get(k, 0)) > 0, "%s 四十年里出现过" % k)
	# 降温：秋冬 21 旬、每旬 10%、同类不叠 → 一年大约 1.9 次
	assert_true(int(counts["cold"]) > 40 and int(counts["cold"]) < 110, "降温次数合理：%d" % int(counts["cold"]))


func test_weather_mean_close_to_one_over_years() -> void:
	var e := EconomyState.new()
	var rng := GameRng.new(17)
	var sum_fixed := 0.0
	var sum_all := 0.0
	var n := 36 * 30
	for p in range(2, n + 2):
		e.period_step(p, 0.0, rng)
		var q := EconomyState.year_q(p)
		sum_fixed += clampf(EconomyState.season_demand(q) * float(EconomyState.calendar(q)[0]) / EconomyState.rhythm_norm(), 0.6, 1.6)
		sum_all += e.rhythm(p)
	assert_near(sum_fixed / n, 1.0, 0.000001, "固定部分年均 = 1.000")
	assert_true(absf(sum_all / n - 1.0) < 0.02, "含天气、夹限后长期均值 0.98–1.02：%f" % (sum_all / n))


func test_intent_and_traffic_carry_rhythm() -> void:
	var trend := {"color": {"red": 1.0}, "pattern": {"solid": 1.0}}
	var base := {"G": 1.0, "material_pref": {"wool": 1.0}}
	var rush := base.duplicate()
	rush["rhythm_intent_add"] = 0.2
	var a := CustomerProfile.generate("a", base, trend, GameRng.new(7))
	var b := CustomerProfile.generate("b", rush, trend, GameRng.new(7))
	assert_near(b.intent, clampf(float(b.derived["intent"]) + 0.2, 0.05, 1.0), 0.0001, "年关意向 +0.20")
	assert_near(a.intent, float(a.derived["intent"]), 0.0001)
	var s := GameState.new_game(5)
	s.clock.period = 35
	s.economy.rhythm_events = [{"kind": "rain", "start": 35, "duration": 1, "traffic_mult": 0.75, "intent_add": 0.0}]
	PeriodRunner.begin_period(s)
	var x := 0.5
	while not s.street.can_place(x):
		x += 0.5
	var stall := StallSession.new(s, x)
	var shop := ShopSession.new(s)
	var g := float(s.econ_now()["G"])
	assert_near(stall._traffic_mult, (0.7 + 0.3 * g) * s.economy.rhythm(35), 0.0001, "摆摊客流 × B")
	assert_near(shop._traffic_mult, (0.7 + 0.3 * g) * s.economy.rhythm(35, true), 0.0001, "店里客流 × B（雨减半）")


func test_traffic_observation_is_divided_by_rhythm() -> void:
	var s := GameState.new_game(3)
	s.clock.period = 36
	PeriodRunner.begin_period(s)
	var b := s.economy.rhythm(36)
	s.period_stats["traffic"] = 100
	PeriodRunner.end_period(s)
	var obs: Dictionary = s.economy.observations[-1]
	assert_near(float(obs["traffic"]), 100.0 / b, 0.0001, "C 的客流观测先除掉 B")


func test_rhythm_events_survive_save_and_old_saves_default_empty() -> void:
	var e := EconomyState.new()
	e.rhythm_events = [{"kind": "sand", "start": 5, "duration": 1, "traffic_mult": 0.8, "intent_add": 0.05}]
	var back := EconomyState.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert_near(back.rhythm(5), e.rhythm(5), 0.000001)
	assert_eq(back.weather_names(5), ["大风沙"])
	var old := EconomyState.from_dict({"base": {"consumption_level": 1.0}})
	assert_eq(old.rhythm_events, [], "老存档没有天气事件")
	assert_near(old.rhythm(5), e.rhythm(5 + 36), 0.000001, "老存档只剩固定节拍")


func test_planning_calendar_and_weather_notice() -> void:
	var t := EconomyState.calendar_outlook(1)
	assert_true(t.contains("本月 1月：年初清淡（上、中旬）、集市日（下旬）"), t)
	assert_true(t.contains("下月 2月：开春集（上旬）、集市日（下旬）"), t)
	assert_true(t.contains("再过 33 旬年关"), t)
	assert_true(t.contains("本旬围巾行情很淡"), t)
	var mid := EconomyState.calendar_outlook(2)
	assert_true(mid.contains("本月 1月：年初清淡（中旬）"), "过去的旬不再列：%s" % mid)
	var rush := EconomyState.calendar_outlook(36 + 35)
	assert_true(rush.contains("年关抢购中") and rush.contains("下月 1月：年初清淡"), rush)
	assert_true(rush.contains("很旺"), rush)
	assert_true(EconomyState.calendar_outlook(14).contains("本月 5月：集市日（下旬）"), "5 月只有月底的集")
	var e := EconomyState.new()
	assert_eq(e.weather_notice(30), "")
	e.rhythm_events = [{"kind": "cold", "start": 30, "duration": 2, "traffic_mult": 1.3, "intent_add": 0.1}]
	assert_eq(e.weather_notice(30), "突然冷了，来买围巾的人多")
	assert_eq(e.weather_notice(31), "还冷着，来买围巾的人还多")
	assert_eq(e.weather_notice(32), "", "过去了就不提")
