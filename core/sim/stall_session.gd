class_name StallSession
extends RefCounted
## 摆摊营业（01 §6.9）：过路客沿人流穿过摊位周遭 N×M 区域时掷逗留判定，逗留者进入客人状态机。
## 表现层和无界面模拟都用它推进；议价交互由调用方处理（headless 用 AutoSeller）。

## 一旬的营业时长（秒，实时，1x 速度）。目标 12–18 分钟，待实测（01 §3.1）。
const PERIOD_SECONDS := 900.0
const BASE_STAY_P := 0.35
## 人流密度 → 每秒过路客数的换算
const TRAFFIC_SCALE := 0.12

signal visitor_arrived(visitor: Dictionary)
signal visitor_left(visitor: Dictionary)
## 每个走过周遭范围的过路客（表现层画行人用）。stayed 表示是否被吸引停下。
signal passerby(stayed: bool)

var s: GameState
var api: ActionAPI
var x: float
## 当前逗留的客人 [{customer, ctx, item_id, state, wait, want, hint}]
## state: browsing 在看 → asking 在问价（等玩家理会）→ haggling 议价中 → waiting_item 谈成了、等你拿货给他
##        → 交货后继续逛（回到 browsing）或离开（left）
## ctx: VisitContext；want: 谈成待交的货 [{item_id, sku_id, price, reserve, done}]；hint: 他指货时你看到的位置描述
var visitors: Array = []
var _spawn_acc := 0.0
var _returning: Array[CustomerProfile] = []


func _init(state: GameState, stall_x: float) -> void:
	s = state
	api = ActionAPI.new(state)
	x = stall_x
	s.stall["x"] = stall_x
	_returning = s.customers.roll_returning(s.rng)


static func can_open_at(state: GameState, stall_x: float) -> bool:
	return state.street.can_place(stall_x)


func area_radius() -> int:
	return int(SkillSystem.shout_mods(s.player)["area_radius"])


func is_over() -> bool:
	return s.clock.time_of_period >= 1.0


## 推进 dt 秒（已乘时间流速）。
func tick(dt: float) -> void:
	if is_over():
		return
	s.clock.time_of_period = minf(1.0, s.clock.time_of_period + dt / PERIOD_SECONDS)
	var t := s.clock.time_of_period
	var width := float(area_radius() * 2 + 1)
	_spawn_acc += s.street.density(x, t) * width * TRAFFIC_SCALE * dt
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		_passerby()
	# 常客在旬内随机时刻回来
	if not _returning.is_empty() and s.rng.chance(dt / PERIOD_SECONDS * 3.0):
		_consider(_returning.pop_back(), true)
	for v in visitors.duplicate():
		if v["state"] == "haggling":
			continue
		v["wait"] = float(v["wait"]) - dt
		if v["wait"] <= 0.0:
			if v["state"] == "asking":
				s.period_stats["ignored"] = int(s.period_stats.get("ignored", 0)) + 1
			elif v["state"] == "waiting_item":
				_lose_deal(v)
			_leave(v)
		elif v["state"] == "browsing" and s.rng.chance(v["customer"].intent * (1.0 - 0.5 * v["customer"].hesitation) * 0.04 * dt):
			# 犹豫一会儿后开口问价
			v["state"] = "asking"
			v["wait"] = 15.0 + 45.0 * v["customer"].patience


## 谈成了却没拿到货就走了：计入流失，常客回购率下降。
func _lose_deal(v: Dictionary) -> void:
	s.period_stats["undelivered"] = int(s.period_stats.get("undelivered", 0)) + 1
	s.customers.penalize(v["customer"], 0.1)


func _leave(v: Dictionary) -> void:
	v["state"] = "left"
	visitors.erase(v)
	visitor_left.emit(v)


func _passerby() -> void:
	s.period_stats["traffic"] = int(s.period_stats["traffic"]) + 1
	var c := CustomerProfile.generate(s.customers.new_customer_id(), s.econ_now(), s.trend_now(), s.rng)
	_consider(c, false)


## 逗留判定：stay_p = base × 吆喝修正 × 偏好匹配度 × 展示度（× 竞争、乱堆修正）。
func _consider(c: CustomerProfile, is_returning: bool) -> void:
	var best := _best_item_for(c)
	if best.is_empty():
		passerby.emit(false)
		return
	var shout := SkillSystem.shout_mods(s.player)
	var sl: Slot = s.inventory.slots[best["slot_id"]]
	var p := BASE_STAY_P * float(shout["stay_mult"]) * (0.3 + 0.7 * float(best["match"])) \
		* sl.display_score * (1.0 - 0.3 * sl.stack.disorder) * (1.0 - s.street.competition(x, area_radius()))
	if is_returning:
		p = maxf(p, 0.7)
	if not s.rng.chance(p):
		passerby.emit(false)
		return
	passerby.emit(true)
	s.period_stats["stayed"] = int(s.period_stats["stayed"]) + 1
	var wants_to_ask := s.rng.chance(clampf(c.intent + float(shout["intent_add"]), 0.0, 1.0))
	var v := {
		"customer": c, "ctx": VisitContext.create(c), "item_id": best["item_id"],
		"state": "asking" if wants_to_ask else "browsing",
		"wait": 20.0 + 60.0 * c.patience, "want": [], "hint": "",
	}
	visitors.append(v)
	visitor_arrived.emit(v)


## 客人在摊位上最想要的那份货。客人只看得到边缘条，按偏好匹配挑。exclude 里的货不挑。
func _best_item_for(c: CustomerProfile, exclude: Array = []) -> Dictionary:
	var best := {}
	var taken := exclude + _promised_items()
	for sl in s.inventory.slots_of_type("StallTable"):
		for i in sl.stack.height():
			if taken.has(sl.stack.items[i].id):
				continue
			var m := c.match_score(sl.stack.items[i].sku_id)
			# 越靠上越容易被看到
			var vis := 1.0 - 0.1 * sl.stack.count_above(i)
			if best.is_empty() or m * vis > float(best["score"]):
				best = {"slot_id": sl.id, "index": i, "item_id": sl.stack.items[i].id, "match": m, "score": m * vis}
	return best


## 客人看中的那份货现在在哪：{slot_id, index}；已不在摊位上（也不在你手上）则为空。
func locate(item_id: String) -> Dictionary:
	for sl in s.inventory.slots_of_type("StallTable") + s.inventory.slots_of_type("Hand"):
		var idx := sl.stack.index_of(item_id)
		if idx >= 0:
			return {"slot_id": sl.id, "index": idx}
	return {}


## 已经谈好、正等着交给别的客人的货（别人不再挑它）。
func _promised_items() -> Array:
	var out := []
	for v in visitors:
		if v["state"] == "waiting_item":
			for w in v["want"]:
				if not w["done"]:
					out.append(w["item_id"])
	return out


## 某款货现在在哪（先摊位后行囊，靠上的优先）：{slot_id, index}。自动模拟找货用。
func find_sku(sku_id: String) -> Dictionary:
	for sl in s.inventory.slots_of_type("StallTable") + s.inventory.slots_of_type("Bag"):
		for i in range(sl.stack.height() - 1, -1, -1):
			if sl.stack.items[i].sku_id == sku_id:
				return {"slot_id": sl.id, "index": i}
	return {}


## 为客人开一个议价。看中的货已经不在（卖掉 / 塌了 / 被挪走）时换一份，没有就返回 null。
## 心理价按同次购物上下文波动；买过东西的客人可以「一起买」，再配一条他也看得上的。
func start_haggle(v: Dictionary) -> HaggleState:
	var loc := locate(v["item_id"])
	if loc.is_empty() or _promised_items().has(v["item_id"]):
		var best := _best_item_for(v["customer"])
		if best.is_empty():
			return null
		v["item_id"] = best["item_id"]
		loc = best
	var sl: Slot = s.inventory.slots[loc["slot_id"]]
	var sku_id: String = sl.stack.items[loc["index"]].sku_id
	var asking := price_of(sku_id)
	var c: CustomerProfile = v["customer"]
	var ctx: VisitContext = v["ctx"]
	ctx.set_budget_from(c, sku_id)
	var mods := SkillSystem.haggle_mods(s.player)
	v["state"] = "haggling"
	var h := HaggleState.start(c, sku_id, asking, mods, ctx)
	if ctx.basket_count >= 1:
		var extra := _best_item_for(c, [v["item_id"]])
		if not extra.is_empty() and float(extra["match"]) > 0.0:
			var extra_sku: String = s.inventory.slots[extra["slot_id"]].stack.items[extra["index"]].sku_id
			h.bundle_extra = {"item_id": extra["item_id"], "sku_id": extra_sku,
				"reserve": HaggleState.reserve_for(c, extra_sku, mods, ctx)}
	return h


func price_of(sku_id: String) -> float:
	return float(s.stall["prices"].get(sku_id, DataDB.sku(sku_id)["base_price"]))


## 议价结束。成交 → 客人等你拿货（waiting_item），不自动出货；没谈成 → 离开。
func finish(v: Dictionary, h: HaggleState) -> void:
	var ctx: VisitContext = v["ctx"]
	if h == null or h.result != "deal":
		if h != null:
			ctx.add_rapport(h.rapport_delta)
		_leave(v)
		return
	ctx.add_rapport(h.rapport_delta)
	ctx.patience = maxf(h.patience_left, 0.05)
	var want := [{"item_id": v["item_id"], "sku_id": h.sku_id, "price": h.final_price, "reserve": h.reserve, "done": false}]
	if h.bundle:
		var r2 := float(h.bundle_extra["reserve"])
		var total := h.total_reserve()
		want[0]["price"] = h.final_price * h.reserve / total
		want.append({"item_id": h.bundle_extra["item_id"], "sku_id": h.bundle_extra["sku_id"],
			"price": h.final_price * r2 / total, "reserve": r2, "done": false})
	v["want"] = want
	v["hint"] = _describe_want(want)
	v["state"] = "waiting_item"
	v["wait"] = wait_for_item(v["customer"])


## 等货时间：约 20 + 40·patience 秒，口才 Lv5 减缓。
func wait_for_item(c: CustomerProfile) -> float:
	return (20.0 + 40.0 * c.patience) * (1.25 if s.player.skill_level("eloquence") >= 5 else 1.0)


## 他指货那一刻你看到的：在哪一格、从上往下第几份、露出的边是什么颜色（认知层，不跟着货走）。
func _describe_want(want: Array) -> String:
	var parts: Array = []
	var a := DataDB.attributes()
	var tables := s.inventory.slots_of_type("StallTable")
	for w in want:
		var color: String = a["colors"][DataDB.sku(w["sku_id"])["color"]]["name"]
		var loc := locate(w["item_id"])
		if loc.is_empty():
			parts.append("一条%s边的" % color)
			continue
		var sl: Slot = s.inventory.slots[loc["slot_id"]]
		if sl.type == "Hand":
			parts.append("你手上那条%s边的" % color)
		else:
			parts.append("摊位 %d 从上往下第 %d 份，露出%s边的那条" % [tables.find(sl) + 1, sl.stack.count_above(loc["index"]) + 1, color])
	return "、".join(parts)


## 把手上的货交给等货的客人（01 §6.4）。
## 返回 {result, paid, count, continued}；result：
##   ok 交齐了 / partial 交了一部分 / wrong 手上不是他要的款 / wrong_left 第二次递错走了 /
##   empty 手上没货（只提示，不扣耐心）/ not_waiting 他没在等货
func deliver(v: Dictionary, hand: Slot) -> Dictionary:
	var out := {"result": "not_waiting", "paid": 0.0, "count": 0, "continued": false}
	if v["state"] != "waiting_item":
		return out
	var c: CustomerProfile = v["customer"]
	var ctx: VisitContext = v["ctx"]
	if hand.stack.height() == 0:
		out["result"] = "empty"
		return out
	for w in v["want"]:
		if w["done"]:
			continue
		# 他指的那一份，或者同款别的一份都行
		var idx := hand.stack.index_of(w["item_id"])
		if idx < 0:
			for i in range(hand.stack.height() - 1, -1, -1):
				if hand.stack.items[i].sku_id == w["sku_id"]:
					idx = i
					break
		if idx < 0:
			continue
		var r := api.sell(hand.id, idx, float(w["price"]), c, float(w["reserve"]))
		if r.get("ok", false):
			w["done"] = true
			out["paid"] = float(out["paid"]) + float(w["price"])
			out["count"] = int(out["count"]) + 1
	if int(out["count"]) == 0:
		ctx.wrong_deliveries += 1
		ctx.add_rapport(-0.3)
		if ctx.wrong_deliveries >= 2:
			_lose_deal(v)
			s.customers.penalize(c, 0.05)
			_leave(v)
			out["result"] = "wrong_left"
		else:
			v["wait"] = maxf(3.0, float(v["wait"]) - 10.0)
			out["result"] = "wrong"
		return out
	ctx.basket_count += int(out["count"])
	ctx.spent += float(out["paid"])
	for w in v["want"]:
		if not w["done"]:
			out["result"] = "partial"
			return out
	out["result"] = "ok"
	v["want"] = []
	# 交齐了：可能接着逛（回到浏览，耐心部分恢复），否则走人
	var next := _best_item_for(c)
	if not next.is_empty() and s.rng.chance(ctx.continue_p(c)):
		ctx.patience = ctx.patience + (c.patience - ctx.patience) * 0.5
		v["item_id"] = next["item_id"]
		v["state"] = "browsing"
		v["wait"] = 15.0 + 40.0 * ctx.patience
		out["continued"] = true
	else:
		_leave(v)
	return out


## 摊位（含地上）、手上、行囊里一共还有几份货。
func goods_left() -> int:
	var n := 0
	for t in ["StallTable", "Hand", "Bag"]:
		for sl in s.inventory.slots_of_type(t):
			n += sl.stack.height() + sl.stack.collapsed_pile.size()
	return n


func table_empty() -> bool:
	for sl in s.inventory.slots_of_type("StallTable"):
		if sl.stack.height() + sl.stack.collapsed_pile.size() > 0:
			return false
	return true


## 有没有客人正在讲价或等货（这时不能自动收摊）。
func busy() -> bool:
	for v in visitors:
		if v["state"] in ["haggling", "waiting_item"]:
			return true
	return false


## 卖光了：所有货都没了，也没有人在讲价或等货（01 §6.9）。
func sold_out() -> bool:
	return goods_left() == 0 and not busy()


## 收摊：所有客人散去，等货的算谈成没拿到货。
func close() -> void:
	for v in visitors.duplicate():
		if v["state"] == "waiting_item":
			_lose_deal(v)
		_leave(v)
