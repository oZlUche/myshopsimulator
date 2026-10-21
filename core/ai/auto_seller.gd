class_name AutoSeller
extends RefCounted
## 无界面模拟用的议价策略：先把说真话的策略用掉（真货比客人看到的更合他意），
## 再从标价起逐轮向客人还价让步，低于成本 +10% 不卖。也是将来员工代卖（02 / 01 §6.5）的雏形。


static func run(h: HaggleState, unit_cost: float, rng: GameRng) -> void:
	var floor_price := unit_cost * 1.1
	var guard := 0
	while h.result == "ongoing" and guard < 16:
		guard += 1
		if h.customer_offer >= floor_price and (h.customer_offer >= h.asking_price * 0.85 or h.patience_left <= 2):
			h.accept_customer_offer()
			return
		var dim := _honest_strategy(h)
		if dim != "":
			h.use_strategy(dim, rng)
			continue
		var q := h.asking_price
		if h.last_quote > 0.0:
			q = maxf(floor_price, (h.last_quote + maxf(h.customer_offer, floor_price)) * 0.5)
		h.offer_price(q, rng)
	if h.result == "ongoing":
		h.choose_option("suggest_other", rng)


## 还没用过、而且说的是真话的策略维度（真货在这一维比客人看到的更接近他想要的）。
static func _honest_strategy(h: HaggleState) -> String:
	var truth := HaggleState.dims_between(h.sku_id, h.expectation)
	for dim in HaggleState.STRATEGIES:
		if not h.strategies_used.has(dim) and float(truth[dim]) < float(h.d_dims[dim]) - 0.001:
			return dim
	return ""


## 用自动策略完整跑一旬营业（headless 模拟 / 存档回归测试用）。返回结算报告。
## 谈成后按真相层直接找到那份货（不翻看、规范手法抽取）拿到手上交货；卖光就提前收摊。
static func simulate_stall_period(s: GameState, stall_x: float = -1.0, step: float = 1.0) -> Dictionary:
	if stall_x < 0.0:
		stall_x = _pick_spot(s)
	var session := StallSession.new(s, stall_x)
	var sold_out := false
	while not session.is_over():
		session.tick(step)
		for v in session.visitors.duplicate():
			if v["state"] != "asking":
				continue
			var h := session.start_haggle(v)
			if h == null:
				session.finish(v, null)
				continue
			var loc := session.locate(v["item_id"])
			var sl: Slot = s.inventory.slots[loc["slot_id"]]
			var cost := float(sl.stack.items[loc["index"]].provenance.get("unit_cost", 0.0))
			run(h, cost, s.rng)
			session.finish(v, h)
			if v["state"] == "waiting_item":
				fetch_and_deliver(session, v)
		if session.sold_out():
			sold_out = true
			break
	session.close()
	var lost := ActionAPI.new(s).pack_up()
	var report := PeriodRunner.end_period(s)
	report["lost_on_pack_up"] = lost
	report["sold_out"] = sold_out
	return report


## 把客人要的货（他指的那份，找不到就同款）拿到手上交给他。
static func fetch_and_deliver(session: StallSession, v: Dictionary) -> Dictionary:
	var hand := session.s.inventory.hand()
	for w in v["want"]:
		if w["done"] or hand.stack.is_full():
			continue
		var loc := session.locate(w["item_id"])
		if not loc.is_empty() and loc["slot_id"] == hand.id:
			continue
		if loc.is_empty():
			loc = session.find_sku(w["sku_id"])
		if loc.is_empty():
			continue
		var r := session.api.pull_item(loc["slot_id"], loc["index"])
		if r["item"] != null:
			session.api.place_on_top(r["item"], hand.id)
	return session.deliver(v, hand)


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
