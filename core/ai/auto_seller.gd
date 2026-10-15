class_name AutoSeller
extends RefCounted
## 无界面模拟用的议价策略：先报标价，逐轮向客人出价让步，低于成本 +10% 不卖。
## 也是将来员工代卖（02 / 01 §6.5）的雏形。


static func run(h: HaggleState, unit_cost: float, rng: GameRng) -> void:
	var floor_price := unit_cost * 1.1
	h.offer_price(h.asking_price, rng)
	var guard := 0
	while h.result == "ongoing" and guard < 6:
		guard += 1
		if h.customer_offer >= floor_price and (guard >= 3 or h.customer_offer >= h.asking_price * 0.85):
			h.accept_customer_offer()
			return
		var next := maxf(floor_price, (h.asking_price + h.customer_offer) * 0.5)
		h.offer_price(next, rng)
	if h.result == "ongoing":
		h.choose_option("suggest_other", rng)


## 用自动策略完整跑一旬营业（headless 模拟 / 存档回归测试用）。返回结算报告。
static func simulate_stall_period(s: GameState, stall_x: float = -1.0, step: float = 1.0) -> Dictionary:
	if stall_x < 0.0:
		stall_x = _pick_spot(s)
	var session := StallSession.new(s, stall_x)
	while not session.is_over():
		session.tick(step)
		for v in session.visitors.duplicate():
			if v["state"] == "asking":
				var h := session.start_haggle(v)
				if h == null:
					session.finish(v, null)
					continue
				var loc := session.locate(v["item_id"])
				var sl: Slot = s.inventory.slots[loc["slot_id"]]
				var cost := float(sl.stack.items[loc["index"]].provenance.get("unit_cost", 0.0))
				run(h, cost, s.rng)
				session.finish(v, h)
	var lost := ActionAPI.new(s).pack_up()
	var report := PeriodRunner.end_period(s)
	report["lost_on_pack_up"] = lost
	return report


## 选一个人流较大且不在商贩排他半径内的位置。
static func _pick_spot(s: GameState) -> float:
	var best_x := 0.5
	var best_d := -1.0
	var px := 0.5
	while px < s.street.length:
		if s.street.can_place(px):
			var d := s.street.density(px) * (1.0 - s.street.competition(px, 2))
			if d > best_d:
				best_d = d
				best_x = px
		px += 0.5
	return best_x


## 自动进货 + 摆摊：把行囊里的货摆上摊位（规划阶段，不计时）。
static func auto_prepare(s: GameState, budget_ratio: float = 0.6) -> void:
	var api := ActionAPI.new(s)
	var budget := s.player.cash * budget_ratio
	for e in s.supplier_catalog:
		var qty := mini(int(e["stock"]), mini(3, api.bag_free_space()))
		if qty <= 0 or float(e["unit_price"]) * qty > budget:
			continue
		if api.purchase(e["sku_id"], qty, float(e["unit_price"]))["ok"]:
			budget -= float(e["unit_price"]) * qty
	for table in s.inventory.slots_of_type("StallTable"):
		for bag in s.inventory.slots_of_type("Bag"):
			while not table.stack.is_full() and bag.stack.height() > 0:
				api.move_item(bag.id, bag.stack.height() - 1, table.id)
