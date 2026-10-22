extends SceneTree
## 节拍层三年验证（09 §1.8）：4 个种子 × 108 旬，AutoSeller 自动摆摊。


func _init() -> void:
	var all_b: Array = []
	var all_k: Array = []
	var all_c: Array = []
	var all_g: Array = []
	var by_q := {}
	var traffic_by_q := {}
	for seed_value in [2026, 7, 42, 99]:
		var s := GameState.new_game(seed_value)
		var year_b := [0.0, 0.0, 0.0]
		for i in 108:
			PeriodRunner.begin_period(s)
			var econ := s.econ_now()
			var b := float(econ["rhythm_mult"])
			var g := float(econ["G"])
			var q := EconomyState.year_q(s.clock.period)
			all_b.append(b)
			all_g.append(g)
			all_k.append((0.7 + 0.3 * g) * b)
			all_c.append(s.economy.continuous_term())
			year_b[i / 36] += b / 36.0
			by_q[q] = float(by_q.get(q, 0.0)) + b / 12.0
			AutoSeller.auto_prepare(s, 0.6)
			var r := AutoSeller.simulate_stall_period(s)
			traffic_by_q[q] = float(traffic_by_q.get(q, 0.0)) + float(r["traffic"]) / 12.0
		print("种子 %d：三年 B 年均 %.3f / %.3f / %.3f，末年 G %.3f，现金 %.0f" % [seed_value, year_b[0], year_b[1], year_b[2], float(s.econ_now()["G"]), s.player.cash])
	print("B 均值 %.4f 范围 %.3f–%.3f" % [_mean(all_b), all_b.min(), all_b.max()])
	print("G 均值 %.3f 范围 %.3f–%.3f" % [_mean(all_g), all_g.min(), all_g.max()])
	print("(0.7+0.3G)·B 均值 %.3f 范围 %.3f–%.3f" % [_mean(all_k), all_k.min(), all_k.max()])
	var abs_c: Array = all_c.map(func(c): return absf(c))
	print("C 均值 %+.4f 范围 %+.3f–%+.3f |C| 均值 %.3f" % [_mean(all_c), all_c.min(), all_c.max(), _mean(abs_c)])
	var line := "年内各旬平均 B / 客流："
	for q in range(1, 37):
		line += "\n  q%02d %.2f %4.0f" % [q, by_q[q], traffic_by_q[q]]
	print(line)
	quit(0)


func _mean(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(1.0, a.size())
