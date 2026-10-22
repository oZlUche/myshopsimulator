extends TestCase
## 成交后手动交货、同次购物上下文、卖光（01 §4.3、§6.4、§6.9）。

const RED := "scarf_solid_red_wool"
const BLUE := "scarf_solid_navy_wool"


func _session() -> StallSession:
	var s := GameState.new_game(5)
	PeriodRunner.begin_period(s)
	var x := 0.5
	while not s.street.can_place(x):
		x += 0.5
	return StallSession.new(s, x)


## agreeable 随和、shrewd 精算（决定 ρ、δ）；不会再逛、不会自己上手拿。
func _customer(s: GameState, agreeable := 0.5, strategy := "tug_of_war", shrewd := 0.5) -> CustomerProfile:
	var c := CustomerProfile.new()
	c.id = s.customers.new_customer_id()
	c.personality = {"sociable": 0.5, "shrewd": shrewd, "composed": 0.5, "fastidious": 0.5, "agreeable": agreeable}
	c.derived = Personality.derive(c.personality)
	c.preference = {"color": "red", "pattern": "solid", "material": "wool"}
	c.patience_n = 6
	c.intent = 0.0
	c.self_serve = 0.0
	c.haggle_strategy = strategy
	return c


## 一位正在问价、会主动开价的客人（挑货在 start_haggle 里当场完成）。
func _visitor(ss: StallSession, c: CustomerProfile, item_id: String) -> Dictionary:
	var v := {"customer": c, "ctx": VisitContext.create(c), "item_id": item_id, "state": "asking",
		"wait": 30.0, "pick": {}, "initiative": true, "p_adj": 0.0, "p_final": 0.0, "want": [], "hint": "", "seen": {}}
	ss.visitors.append(v)
	return v


## 摆几份货到第一格摊位，返回该格。
func _table(ss: StallSession, skus: Array) -> Slot:
	var t: Slot = ss.s.inventory.slots_of_type("StallTable")[0]
	for sku in skus:
		ss.api.place_on_top(ss.s.inventory.create_item(sku), t.id)
	return t


## 谈成一单：客人直接接受你的报价。
func _deal(ss: StallSession, v: Dictionary) -> HaggleState:
	var h := ss.start_haggle(v)
	h.accept_customer_offer()
	ss.finish(v, h)
	return h


func test_deal_waits_for_item_then_delivers() -> void:
	var ss := _session()
	var t := _table(ss, [RED, BLUE])
	var v := _visitor(ss, _customer(ss.s), t.stack.items[0].id)
	var cash := ss.s.player.cash
	var h := _deal(ss, v)
	assert_eq(v["state"], "waiting_item", "谈成后进入等货")
	assert_eq(int(ss.s.period_stats["sales"]), 0, "不自动出货")
	assert_eq(t.stack.height(), 2)
	assert_true(String(v["hint"]).contains("摊位 1"), "提示按你看到的位置描述：%s" % v["hint"])
	var hand := ss.s.inventory.hand()
	var r := ss.api.pull_item(t.id, 0)
	ss.api.place_on_top(r["item"], hand.id)
	var d := ss.deliver(v, hand)
	assert_eq(d["result"], "ok")
	assert_eq(int(ss.s.period_stats["sales"]), 1)
	assert_near(ss.s.player.cash, cash + h.final_price)
	assert_eq(hand.stack.height(), 0)
	assert_eq(v["ctx"].basket_count, 1)


func test_same_sku_other_item_is_accepted() -> void:
	var ss := _session()
	var t := _table(ss, [RED, RED])
	var v := _visitor(ss, _customer(ss.s), t.stack.items[0].id)
	_deal(ss, v)
	var hand := ss.s.inventory.hand()
	ss.api.take_top_to_hand(t.id)   # 拿的是上面那份同款
	assert_eq(ss.deliver(v, hand)["result"], "ok")


func test_empty_hand_only_hints() -> void:
	var ss := _session()
	var t := _table(ss, [RED])
	var v := _visitor(ss, _customer(ss.s), t.stack.items[0].id)
	_deal(ss, v)
	var w := float(v["wait"])
	assert_eq(ss.deliver(v, ss.s.inventory.hand())["result"], "empty")
	assert_eq(v["state"], "waiting_item")
	assert_near(float(v["wait"]), w, 0.0001, "空手点客人不扣耐心")


func test_wrong_item_twice_and_he_leaves() -> void:
	var ss := _session()
	var t := _table(ss, [RED, BLUE])
	var c := _customer(ss.s)
	var v := _visitor(ss, c, t.stack.items[0].id)
	_deal(ss, v)
	var hand := ss.s.inventory.hand()
	ss.api.take_top_to_hand(t.id)   # 蓝的
	var w := float(v["wait"])
	var r0: float = v["ctx"].rapport
	assert_eq(ss.deliver(v, hand)["result"], "wrong")
	assert_eq(hand.stack.height(), 1, "递错的货留在手上")
	assert_true(float(v["wait"]) < w, "等待时间扣一截")
	assert_true(v["ctx"].rapport < r0, "递错好感下降")
	assert_eq(ss.deliver(v, hand)["result"], "wrong_left")
	assert_eq(v["state"], "left")
	assert_eq(int(ss.s.period_stats["lost_after_deal"]), 1)


func test_timeout_counts_lost_deal_and_hurts_regular() -> void:
	var ss := _session()
	var t := _table(ss, [RED])
	var c := _customer(ss.s)
	ss.s.customers.record_purchase(c, 10.0, 10.0)   # 已是常客
	var p0: float = ss.s.customers.return_probability[c.id]
	var v := _visitor(ss, c, t.stack.items[0].id)
	_deal(ss, v)
	ss.api.take_top_to_hand(t.id)   # 拿到手上却一直没点他
	ss.tick(float(v["wait"]) + 1.0)
	assert_eq(v["state"], "left")
	assert_eq(int(ss.s.period_stats["lost_after_deal"]), 1)
	assert_true(float(ss.s.customers.return_probability[c.id]) < p0, "常客没拿到货回购率下降")


func test_self_serve_when_goods_still_on_table() -> void:
	var ss := _session()
	var t := _table(ss, [RED, BLUE])
	var c := _customer(ss.s)
	c.self_serve = 1.0
	var v := _visitor(ss, c, t.stack.items[0].id)
	var h := _deal(ss, v)
	var got := []
	ss.self_served.connect(func(vv, r): got.append(r))
	var cash := ss.s.player.cash
	ss.tick(float(v["wait"]) + 1.0)
	assert_eq(got.size(), 1, "等不到人，自己上手拿")
	assert_eq(int(ss.s.period_stats["sales"]), 1)
	assert_near(ss.s.player.cash, cash + h.final_price, 0.0001, "按谈好的价付钱")
	assert_eq(int(ss.s.period_stats["lost_after_deal"]), 0)
	assert_eq(v["state"], "left")


func test_several_customers_wait_at_once() -> void:
	var ss := _session()
	var t := _table(ss, [RED, RED, RED])
	var a := _visitor(ss, _customer(ss.s), t.stack.items[0].id)
	var b := _visitor(ss, _customer(ss.s), t.stack.items[1].id)
	_deal(ss, a)
	_deal(ss, b)
	assert_eq(a["state"], "waiting_item")
	assert_eq(b["state"], "waiting_item")
	assert_true(a["want"][0]["item_id"] != b["want"][0]["item_id"], "别人等着的那份不会再被挑")


func test_reserve_drifts_with_visit_context() -> void:
	var s := GameState.new_game(1)
	var kind := _customer(s, 1.0, "tug_of_war")
	kind.visits = 6
	var ctx := VisitContext.create(kind)
	ctx.set_budget_from(kind, RED)
	ctx.basket_count = 1
	ctx.rapport = 1.0
	var base := HaggleState.reserve_for(kind, RED)
	assert_true(ctx.drift_reserve(kind, base) > base, "熟了好说话：给个好价")
	var tough := _customer(s, 0.0, "direct_discount", 1.0)
	var ctx2 := VisitContext.create(tough)
	ctx2.set_budget_from(tough, RED)
	ctx2.basket_count = 2
	var base2 := HaggleState.reserve_for(tough, RED)
	assert_true(ctx2.drift_reserve(tough, base2) < base2, "爱砍价：买多要优惠")
	var h := HaggleState.start(tough, RED, 100.0, {"initiative": true}, {}, ctx2, GameRng.new(1))
	assert_true(h.last_line.contains("便宜点"), h.last_line)
	# 预算花得差不多了，心理价被剩余预算封顶，也不会再逛
	ctx2.spent = ctx2.budget - 1.0
	assert_true(ctx2.drift_reserve(tough, base2) <= 1.0 + 0.0001)
	assert_true(ctx2.again_p(tough, 1.0) < 0.05)


func test_bundle_sells_two_for_one_total() -> void:
	var ss := _session()
	var t := _table(ss, [RED, RED, BLUE])
	var c := _customer(ss.s)
	var v := _visitor(ss, c, t.stack.items[0].id)
	v["ctx"].basket_count = 1
	var h := ss.start_haggle(v)
	assert_true(h.bundle_available(), "买过一件后可以一起买")
	h.offer_bundle(1.0, ss.s.rng)   # 远低于客人出价，必成
	assert_eq(h.result, "deal")
	ss.finish(v, h)
	assert_eq(v["want"].size(), 2)
	var hand := ss.s.inventory.hand()
	for w in v["want"]:
		var loc := ss.locate(w["item_id"])
		ss.api.place_on_top(ss.api.pull_item(loc["slot_id"], loc["index"])["item"], hand.id)
	var d := ss.deliver(v, hand)
	assert_eq(d["count"], 2)
	assert_near(float(d["paid"]), 1.0, 0.0001, "两条按总价收")


func test_bundle_failure_costs_more_patience() -> void:
	var ss := _session()
	var t := _table(ss, [RED, RED])
	var v := _visitor(ss, _customer(ss.s), t.stack.items[0].id)
	v["ctx"].basket_count = 1
	var h := ss.start_haggle(v)
	var single := HaggleState.start(v["customer"], RED, h.asking_price, {"initiative": true}, {}, v["ctx"], ss.s.rng)
	var p0 := h.patience_left
	h.offer_bundle(99999.0, ss.s.rng)
	single.offer_price(99999.0, ss.s.rng)
	assert_true(p0 - h.patience_left > p0 - single.patience_left)


func test_sold_out_detection() -> void:
	var ss := _session()
	for b in ss.s.inventory.slots_of_type("Bag"):
		b.stack.items.clear()
	assert_true(ss.sold_out(), "什么都没有、没人等货 → 卖光")
	var t := _table(ss, [RED])
	assert_true(not ss.sold_out())
	var v := _visitor(ss, _customer(ss.s), t.stack.items[0].id)
	_deal(ss, v)
	var hand := ss.s.inventory.hand()
	ss.api.take_top_to_hand(t.id)
	assert_true(not ss.sold_out(), "货在手上还没交")
	ss.deliver(v, hand)
	assert_true(ss.sold_out())
	# 摊上空了但行囊还有：不算卖光
	ss.api.place_on_top(ss.s.inventory.create_item(RED), ss.s.inventory.slots_of_type("Bag")[0].id)
	assert_true(ss.table_empty() and not ss.sold_out())


func test_cost_shown_from_provenance_or_estimated() -> void:
	var ss := _session()
	var t := _table(ss, [RED])
	var bought := ss.s.inventory.create_item(BLUE, {"unit_cost": 23.5})
	ss.api.place_on_top(bought, t.id)
	assert_eq(ss.cost_of(bought.id, BLUE), {"cost": 23.5, "estimated": false}, "有进价记录就用实际进价")
	var old := ss.cost_of(t.stack.items[0].id, RED)
	assert_true(old["estimated"], "没有记录的老货标「约」")
	assert_true(float(old["cost"]) > 0.0)
	ss.s.supplier_catalog = [{"sku_id": RED, "unit_price": 30.0, "stock": 5}]
	assert_near(float(ss.cost_of(t.stack.items[0].id, RED)["cost"]), 30.0, 0.0001, "按当前本地进货价估算")


func test_reask_first_free_then_may_annoy_and_he_leaves() -> void:
	var ss := _session()
	var t := _table(ss, [RED])
	var c := _customer(ss.s, 0.0, "tug_of_war", 1.0)
	c.personality["composed"] = 0.0
	ss.s.customers.record_purchase(c, 10.0, 10.0)   # 已是常客
	var p0: float = ss.s.customers.return_probability[c.id]
	var v := _visitor(ss, c, t.stack.items[0].id)
	_deal(ss, v)
	var ctx: VisitContext = v["ctx"]
	var w := float(v["wait"])
	var r := ss.reask(v)
	assert_eq(r["result"], "reask", "第一次再问免费")
	assert_eq(r["hint"], v["hint"], "说的和成交那一刻一样")
	assert_near(ctx.mood, 0.0)
	assert_near(float(v["wait"]), w)
	assert_near(ss.p_annoy(c), 0.75, 0.0001, "精算、不随和、不沉稳：0.2 + 0.4 + 0.15")
	var annoyed := 0
	for i in 60:
		var rapport := ctx.rapport
		w = float(v["wait"])
		r = ss.reask(v)
		if r["result"] == "reask":
			continue
		annoyed += 1
		assert_near(ctx.rapport, rapport - 0.1, 0.0001, "不耐烦：好感 −0.1")
		assert_near(ctx.mood, -0.25 * annoyed, 0.0001, "心情 −0.25")
		if r["result"] == "reask_left":
			break
		assert_near(float(v["wait"]), w * 0.8, 0.0001, "剩余等待 ×0.8")
	assert_eq(annoyed, 3, "心情掉到 −0.75（< −0.5）才走")
	assert_eq(v["state"], "left")
	assert_eq(v.get("left_reason", ""), "mood")
	assert_eq(int(ss.s.period_stats["lost_after_deal"]), 1)
	assert_near(float(ss.s.customers.return_probability[c.id]), p0 - 0.05, 0.0001, "常客回购率 −0.05")
	assert_eq(ss.reask(v)["result"], "not_waiting")


func test_p_annoy_bounds_and_eloquence() -> void:
	var ss := _session()
	var calm := _customer(ss.s, 1.0, "tug_of_war", 0.0)
	calm.personality["composed"] = 1.0
	assert_near(ss.p_annoy(calm), 0.05, 0.0001, "随和沉稳、不精算：夹到 0.05")
	var mid := _customer(ss.s)
	assert_near(ss.p_annoy(mid), 0.2 + 0.2 - 0.125 + 0.075, 0.0001)
	ss.s.player.skills["eloquence"] = {"level": 3, "invested": 0.0}
	assert_near(ss.p_annoy(mid), (0.2 + 0.2 - 0.125 + 0.075) * 0.7, 0.0001, "口才 Lv3 起 ×0.7")


func test_waiting_and_wrong_items_wear_mood_down() -> void:
	var ss := _session()
	var t := _table(ss, [RED, BLUE])
	var v := _visitor(ss, _customer(ss.s), t.stack.items[0].id)
	_deal(ss, v)
	var ctx: VisitContext = v["ctx"]
	var total := float(v["wait"])
	ss.tick(total * 0.26)
	assert_near(ctx.mood, -0.1, 0.0001, "等过 25%：心情 −0.1")
	ss.tick(total * 0.25)
	assert_near(ctx.mood, -0.2, 0.0001, "等过 50%：再 −0.1")
	assert_eq(v["state"], "waiting_item")
	ss.api.take_top_to_hand(t.id)   # 蓝的
	ctx.mood = -0.4
	assert_eq(ss.deliver(v, ss.s.inventory.hand())["result"], "wrong_mood_left", "递错 −0.15，掉到底直接走")
	assert_eq(v["state"], "left")
	assert_eq(int(ss.s.period_stats["lost_after_deal"]), 1)


func test_bad_mood_leaves_while_waiting() -> void:
	var ss := _session()
	var t := _table(ss, [RED])
	var c := _customer(ss.s)
	c.self_serve = 1.0
	var v := _visitor(ss, c, t.stack.items[0].id)
	_deal(ss, v)
	v["ctx"].mood = -0.35
	var got := []
	ss.self_served.connect(func(vv, r): got.append(r))
	for i in 20:
		ss.tick(float(v["wait_total"]) * 0.05)
	assert_eq(v["state"], "left", "−0.35 等过一半掉到 −0.55，不等到头就走")
	assert_eq(v.get("left_reason", ""), "mood")
	assert_eq(got.size(), 0, "心情差走的不会自己上手拿")
	assert_eq(int(ss.s.period_stats["lost_after_deal"]), 1)


func test_mood_hint_needs_observation_lv2() -> void:
	var p := PlayerState.new()
	var ctx := VisitContext.new()
	ctx.mood = -0.3
	assert_eq(Sampler.mood_hint(ctx, p), "", "看不出来")
	p.skills["customer_observation"] = {"level": 2, "invested": 0.0}
	assert_eq(Sampler.mood_hint(ctx, p), "有点不耐烦了")
	ctx.mood = -0.45
	assert_eq(Sampler.mood_hint(ctx, p), "快没耐心了")
	ctx.mood = 0.1
	assert_eq(Sampler.mood_hint(ctx, p), "")
	var rng := GameRng.new(3)
	for i in 20:
		var m := VisitContext.create(CustomerProfile.new(), rng).mood
		assert_true(m >= -0.2 and m <= 0.2, "来访时的心情 −0.2..0.2")
