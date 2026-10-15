extends SceneTree
## 数值探针：自动玩若干旬，打印每旬客流 / 成交 / 现金，用于调参。
##   godot --headless --path . --script res://tests/tools/balance_probe.gd


func _init() -> void:
	var s := GameState.new_game(2026)
	for i in 12:
		PeriodRunner.begin_period(s)
		AutoSeller.auto_prepare(s, 0.6)
		var r := AutoSeller.simulate_stall_period(s)
		print("%s 客流%4d 逗留%3d 成交%3d 营业额%7.1f 进货%7.1f 现金%8.1f 经验%5.1f 行囊%2d 塌%d" % [
			r["label"], r["traffic"], r["stayed"], r["sales"], r["revenue"], r["purchases"], r["cash"],
			s.player.xp_pool, s.inventory.count_items("player", "Bag"), r["collapses"]])
	quit(0)
