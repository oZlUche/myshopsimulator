class_name PeriodRunner
extends RefCounted
## 旬的开始与旬末结算（01 §3）。规划阶段时间冻结；营业由 StallSession 推进。


## 旬初：刷新进货目录、街区、默认标价。
static func begin_period(s: GameState) -> void:
	s.clock.time_of_period = 0.0
	s.reset_period_stats()
	s.supplier_catalog = LocalSupplier.refresh_catalog(s.econ_now(), s.rng)
	s.street = Street.generate(s.rng)
	s.stall["x"] = null
	for e in s.supplier_catalog:
		if not s.stall["prices"].has(e["sku_id"]):
			s.stall["prices"][e["sku_id"]] = s.list_price(e["sku_id"])
	s.bus.emit("period_begin", {"period": s.clock.period})


## 旬末结算：观测入经济循环、趋势漂移、审美预报、年末宏观调整、时钟推进、物价等宏观状态走一步。返回结算报告。
static func end_period(s: GameState) -> Dictionary:
	var g_prev := s.economy.level() - 1.0
	var st := s.period_stats
	var sales := int(st["sales"])
	var report := {
		"period": s.clock.period,
		"label": s.clock.label(),
		"traffic": st["traffic"], "stayed": st["stayed"], "sales": sales,
		"revenue": st["revenue"], "cost_of_goods": st["cost_of_goods"], "purchases": st["purchases"],
		"collapses": st["collapses"], "xp_earned": st["xp_earned"], "ignored": st.get("ignored", 0),
		"no_match": st.get("no_match", 0), "scared_off": st.get("scared_off", 0),
		"lost_after_deal": st.get("lost_after_deal", st.get("undelivered", 0)),
		"cash": s.player.cash,
		"forecasts": [],
		"season_changed": false, "year_changed": false,
	}
	var ratio := (float(st["price_ratio_sum"]) / sales - 1.0) if sales > 0 else 0.0
	s.economy.push_observation({"price_ratio": ratio, "sales": sales, "traffic": int(st["traffic"])})
	s.trend.step(s.clock.period, s.rng)
	var fc := Sampler.trend_forecast(s.trend, s.clock.period, s.player, s.rng)
	s.knowledge.trend_hints.append_array(fc)
	report["forecasts"] = fc
	if Clock.is_year_end(s.clock.period):
		report["year_delta"] = s.economy.year_end_step(s.rng)
		report["year_changed"] = true
	var old_season := s.clock.season()
	s.clock.period += 1
	s.economy.period_step(s.clock.period, g_prev, s.rng)
	report["season_changed"] = s.clock.season() != old_season
	s.bus.emit("period_end", report)
	return report
