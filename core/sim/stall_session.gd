class_name StallSession
extends RefCounted
## 摆摊营业（01 §6.9、06 §3）：过路客沿人流穿过摊位周遭 N×M 区域时掷逗留判定，逗留者进入客人状态机。
## 表现层和无界面模拟都用它推进；议价交互由调用方处理（headless 用 AutoSeller）。

## 一旬的营业时长（秒，实时，1x 速度）。目标 12–18 分钟，待实测（01 §3.1）。
const PERIOD_SECONDS := 900.0
const BASE_STAY_P := 0.6
## 人流密度 → 每秒过路客数的换算
const TRAFFIC_SCALE := 0.12
## 合拍客人保底计时器（06 §3.1）：间隔 T = T0 / (1 + k·摊上货物份数)
const FIT_T0 := 90.0
const FIT_K := 0.08
## 等货时再问一次（06 §3.6）：耗时；不耐烦、递错、每等过 25% 时心情各掉多少
const REASK_SECONDS := 2.0
const REASK_MOOD_STEP := 0.25
const WRONG_MOOD_STEP := 0.15
const WAIT_MOOD_STEP := 0.1

signal visitor_arrived(visitor: Dictionary)
signal visitor_left(visitor: Dictionary)
## 每个走过周遭范围的过路客（表现层画行人用）。stayed 表示是否被吸引停下。
signal passerby(stayed: bool)
## 等货等到头，客人自己上手拿了（06 §3.6）。r 为 ActionAPI.npc_fetch 的结果。
signal self_served(visitor: Dictionary, r: Dictionary)

var s: GameState
var api: ActionAPI
var x: float
## 当前逗留的客人 [{customer, ctx, state, wait, item_id, pick, initiative, p_adj, p_final, want, hint, seen}]
## state: browsing 在挑（挑完找到 → asking，找不到 → 走）→ asking 在问价（等玩家理会）→ haggling 议价中
##        → waiting_item 谈成了、等你拿货给他 → 交货后再逛（回到 browsing）或离开（left）
## ctx: VisitContext；pick: 挑中的货 {item_id, perceived_sku, exp_index, d, tol}；p_adj: 别人闹场等带来的 P 增减；
## want: 谈成待交的货 [{item_id, sku_id, price, reserve, exp_index, done}]；hint: 他指货时你看到的位置描述；
## seen: 他对每份货的观感缓存 {item_id: {noticed, sku}}（看走眼一次就一直那么以为）
var visitors: Array = []
var _spawn_acc := 0.0
var _fit_acc := 0.0
## 计时器到点了：下一位过路客按摊上实际摆着的货生成
var _fit_pending := false
var _returning: Array[CustomerProfile] = []
## 景气和节拍对客流的修正 (0.7 + 0.3·G) · B（09 §3.3、§1.8），一旬里不变
var _traffic_mult := 1.0


func _init(state: GameState, stall_x: float, returning: Variant = null) -> void:
	s = state
	api = ActionAPI.new(state)
	x = stall_x
	if not is_nan(stall_x):
		s.stall["x"] = stall_x
	if returning == null:
		_returning = s.customers.roll_returning(s.rng)
	else:
		_returning.assign(returning)
	var econ := s.econ_now()
	_traffic_mult = (0.7 + 0.3 * float(econ["G"])) * float(econ.get("rhythm_mult_indoor" if indoor() else "rhythm_mult", 1.0))


## 这一旬还没回来的常客（店面和仓库来回跑时要接着用，别让同一个常客回来两次）。
func returning_left() -> Array[CustomerProfile]:
	return _returning


# ---------- 场地（摊位 / 店面各自覆盖） ----------
## 客人看得到、挑得到的货格。
func display_slots() -> Array[Slot]:
	return s.inventory.slots_of_type("StallTable")


func is_display(sl: Slot) -> bool:
	return sl.type == "StallTable"


## 室内（店面）：雨天对客流的影响减半（09 §1.8）。摆摊在街上。
func indoor() -> bool:
	return false


## 找货时还会翻的地方（自动模拟用）：摊位上找不到就去行囊里。
func storage_slots() -> Array[Slot]:
	return s.inventory.slots_of_type("Bag")


## 提示里怎么叫这一格：「摊位 2」。
func slot_title(sl: Slot) -> String:
	return "摊位 %d" % (display_slots().find(sl) + 1)


## 每秒新来多少过路客（景气修正在 tick 里乘）。
func spawn_rate(t: float) -> float:
	var width := float(area_radius() * 2 + 1)
	return s.street.density(x, t) * width * TRAFFIC_SCALE


## 场地对逗留的修正：吆喝 × 同街竞争。
func venue_stay_mult() -> float:
	return float(SkillSystem.shout_mods(s.player)["stay_mult"]) * (1.0 - s.street.competition(x, area_radius()))


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
	_spawn_acc += spawn_rate(s.clock.time_of_period) * _traffic_mult * dt
	_fit_acc += dt
	if _fit_acc >= fit_interval():
		_fit_acc = 0.0
		_fit_pending = true
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		_passerby()
	# 常客在旬内随机时刻回来
	if not _returning.is_empty() and s.rng.chance(dt / PERIOD_SECONDS * 3.0):
		var c: CustomerProfile = _returning.pop_back()
		c.apply_economy(s.econ_now())
		_consider(c, true)
	for v in visitors.duplicate():
		if v["state"] == "haggling":
			continue
		v["wait"] = float(v["wait"]) - dt
		if v["wait"] > 0.0:
			if v["state"] == "waiting_item":
				_wait_mood(v)
			continue
		match v["state"]:
			"browsing":
				_finish_browsing(v)
			"asking":
				s.period_stats["ignored"] = int(s.period_stats.get("ignored", 0)) + 1
				_leave(v)
			"waiting_item":
				_wait_ran_out(v)
			_:
				_leave(v)


## 挑完了：有在容差内的货就开口，没有就"看了看走了"（06 §3.2）。
func _finish_browsing(v: Dictionary) -> void:
	var pick := _pick(v)
	if pick.is_empty():
		s.period_stats["no_match"] = int(s.period_stats.get("no_match", 0)) + 1
		_leave(v)
		return
	var c: CustomerProfile = v["customer"]
	v["pick"] = pick
	v["item_id"] = pick["item_id"]
	v["state"] = "asking"
	v["wait"] = 15.0 + 45.0 * c.patience
	# 主动开价还是问"多少钱"（06 §3.3），吆喝 Lv3 让人更愿意开口
	var shout := SkillSystem.shout_mods(s.player)
	v["initiative"] = s.rng.chance(clampf(c.initiative + float(shout["intent_add"]), 0.0, 1.0))


## 等货等到头（06 §3.6）：货还摆在摊上 → 按 self_serve 自己上手拿、按谈好的价付钱；
## 否则转身走（谈成没拿到货）。货在你手上或已经没了，好感和回购率再扣。
func _wait_ran_out(v: Dictionary) -> void:
	var c: CustomerProfile = v["customer"]
	var ctx: VisitContext = v["ctx"]
	var missing := false
	for w in v["want"]:
		if w["done"]:
			continue
		var loc := locate(w["item_id"])
		var on_table: bool = not loc.is_empty() and is_display(s.inventory.slots[loc["slot_id"]])
		if on_table and s.rng.chance(c.self_serve):
			var r := api.npc_fetch(loc["slot_id"], loc["index"], c.to_actor_profile())
			if r["item"] != null:
				api.sell_item(r["item"], float(w["price"]), c, float(w["reserve"]))
				w["done"] = true
				ctx.basket_count += 1
				ctx.spent += float(w["price"])
				self_served.emit(v, r)
				continue
		missing = true
		if not on_table:
			ctx.add_rapport(-0.3)
			s.customers.penalize(c, 0.1)
	if missing:
		s.period_stats["lost_after_deal"] = int(s.period_stats.get("lost_after_deal", 0)) + 1
	_leave(v)


## 等货等得越久心情越差（06 §3.6）：每过等待时间的 25% 心情 −0.1，掉到底就走。
func _wait_mood(v: Dictionary) -> void:
	var total := float(v.get("wait_total", 0.0))
	if total <= 0.0:
		return
	var marks := mini(int((total - float(v["wait"])) / (total * 0.25)), 3)
	var ctx: VisitContext = v["ctx"]
	while int(v.get("wait_marks", 0)) < marks:
		v["wait_marks"] = int(v.get("wait_marks", 0)) + 1
		if ctx.lower_mood(WAIT_MOOD_STEP):
			_mood_leave(v)
			return


## 心情太低：「算了，不要了」立刻走（06 §3.6），算谈成没拿到货，常客回购率 −0.05。
func _mood_leave(v: Dictionary) -> void:
	v["left_reason"] = "mood"
	_lose_deal(v, 0.05)
	_leave(v)


## 谈成了却没拿到货就走了（递错两次 / 收摊）：计入流失，常客回购率下降。
func _lose_deal(v: Dictionary, penalty: float = 0.1) -> void:
	s.period_stats["lost_after_deal"] = int(s.period_stats.get("lost_after_deal", 0)) + 1
	s.customers.penalize(v["customer"], penalty)


func _leave(v: Dictionary) -> void:
	v["state"] = "left"
	visitors.erase(v)
	visitor_left.emit(v)


func _passerby() -> void:
	s.period_stats["traffic"] = int(s.period_stats["traffic"]) + 1
	var c := CustomerProfile.generate(s.customers.new_customer_id(), s.econ_now(), s.trend_now(), s.rng)
	if _fit_pending and _fit_to_stall(c):
		_fit_pending = false
	_consider(c, false)


## 合拍客人保底的间隔：货摆得越多，越快等到一位（10 份约 50 秒，25 份约 30 秒）。
func fit_interval() -> float:
	return FIT_T0 / (1.0 + FIT_K * table_goods())


## 合拍客人（06 §3.1）：第一条预期值对准摊上实际摆着的某一份货，热闹偏好调到眼下最受用的一头。
## 人本身照常从原型里抽（generate 已经抽过）。摊上没货返回 false。
func _fit_to_stall(c: CustomerProfile) -> bool:
	var pool: Array = []
	for sl in display_slots():
		pool.append_array(sl.stack.items)
	if pool.is_empty():
		return false
	var sku := DataDB.sku(s.rng.pick(pool).sku_id)
	c.preference = {"color": sku["color"], "pattern": sku["pattern"], "material": sku["material"]}
	# m_crowd = 0.55 + c·(H − 0.55)：H 高就让他爱热闹，H 低就让他爱清净，取到 max(H, 1.1 − H)
	c.crowd_pref = 1.0 if heat() >= 0.55 else -1.0
	return true


## 摊位上摆着几份货（不算地上塌的）。
func table_goods() -> int:
	var n := 0
	for sl in display_slots():
		n += sl.stack.height()
	return n


## 摊位热闹程度 H ∈ [0.1, 1]（06 §3.1）：摊前的人越多、摆的货越多越热闹。
func heat() -> float:
	return clampf(0.1 + 0.3 * visitors.size() + 0.03 * table_goods(), 0.1, 1.0)


## 热闹偏好 c ∈ [−1, 1] 对停留的倍率：c = 1 最爱热闹（= H），c = −1 最爱清净（= 1.1 − H），c = 0 无所谓（0.55）。
static func m_crowd(c: float, h: float) -> float:
	return (1.0 + c) * 0.5 * h + (1.0 - c) * 0.5 * (1.1 - h)


## 逗留判定（06 §3.1）：stay_p = base × m_crowd(c, H) × 吆喝 × 展示度 × 偏好匹配（× 乱堆、竞争修正）。
## 偏好匹配 = 第一条想要的与摊上最接近那份（按他看到的）的 1 − d/tol，夹到 0.3..1。
func _consider(c: CustomerProfile, is_returning: bool) -> void:
	if table_goods() == 0:
		passerby.emit(false)
		return
	var v := {
		"customer": c, "ctx": VisitContext.create(c, s.rng), "state": "browsing", "wait": 0.0,
		"item_id": "", "pick": {}, "initiative": false, "p_adj": 0.0, "p_final": 0.0,
		"want": [], "hint": "", "seen": {},
	}
	var mods := SkillSystem.haggle_mods(s.player)
	var tol: float = v["ctx"].tolerance(c, float(mods["tol_add"]))
	var best_d := INF
	var best_slot: Slot = null
	for sl in display_slots():
		for i in sl.stack.height():
			var seen := _see(v, sl, i)
			var d := AttrDistance.to_expectation(seen["sku"], c.expectations[0])
			if d < best_d:
				best_d = d
				best_slot = sl
	var match_f := clampf(1.0 - best_d / tol, 0.3, 1.0)
	var p := BASE_STAY_P * m_crowd(c.crowd_pref, heat()) * venue_stay_mult() * match_f \
		* best_slot.display_score * (1.0 - 0.3 * best_slot.stack.disorder)
	if is_returning:
		p = maxf(p, 0.7)
	if not s.rng.chance(p):
		passerby.emit(false)
		return
	passerby.emit(true)
	s.period_stats["stayed"] = int(s.period_stats["stayed"]) + 1
	v["wait"] = browse_time(c)
	visitors.append(v)
	visitor_arrived.emit(v)


## 挑货要花的时间：每看一份 0.4 + 1.6·(1 − 挑选速度) 秒（06 §3.2），最多看 12 份。
func browse_time(c: CustomerProfile) -> float:
	return mini(table_goods(), 12) * (0.4 + 1.6 * (1.0 - c.browse_speed))


## 他眼里的这份货：注没注意到（越往下越容易被忽略），以及看成了什么（图案看边缘、材质靠猜，可能看走眼）。
## 第一次看到时掷一次并记住。
func _see(v: Dictionary, sl: Slot, i: int) -> Dictionary:
	var item: ScarfItem = sl.stack.items[i]
	var cache: Dictionary = v["seen"]
	if not cache.has(item.id):
		var sku := DataDB.sku(item.sku_id)
		cache[item.id] = {
			"noticed": s.rng.chance(1.0 - 0.1 * sl.stack.count_above(i)),
			"sku": "scarf_%s_%s_%s" % [_guess(AttrDistance.pattern_confusion(sku["pattern"]), sku["pattern"]),
				sku["color"], _guess(AttrDistance.material_confusion(sku["material"]), sku["material"])],
		}
	return cache[item.id]


func _guess(conf: Dictionary, truth: String) -> String:
	var roll := s.rng.randf()
	for q in conf:
		roll -= float(conf[q])
		if roll < 0.0:
			return q
	return truth


## 按预期值的优先级扫一遍摊上注意到的货，挑差值最小且在容差内的那份（06 §3.2）。
## 返回 {item_id, slot_id, index, perceived_sku, exp_index, d, tol}；一份都没有返回空。
func _pick(v: Dictionary, exclude: Array = []) -> Dictionary:
	var c: CustomerProfile = v["customer"]
	var ctx: VisitContext = v["ctx"]
	var tol := ctx.tolerance(c, float(SkillSystem.haggle_mods(s.player)["tol_add"]))
	var taken := exclude + _promised_items()
	for ei in ctx.remaining_expectations(c):
		var best := {}
		for sl in display_slots():
			for i in sl.stack.height():
				var item: ScarfItem = sl.stack.items[i]
				if taken.has(item.id):
					continue
				var seen := _see(v, sl, i)
				if not seen["noticed"]:
					continue
				var d := AttrDistance.to_expectation(seen["sku"], c.expectations[ei])
				if d <= tol and (best.is_empty() or d < float(best["d"])):
					best = {"item_id": item.id, "slot_id": sl.id, "index": i, "perceived_sku": seen["sku"],
						"exp_index": ei, "d": d, "tol": tol}
		if not best.is_empty():
			return best
	return {}


## 客人看中的那份货现在在哪：{slot_id, index}；已不在摊位上（也不在你手上）则为空。
func locate(item_id: String) -> Dictionary:
	for sl in display_slots() + s.inventory.slots_of_type("Hand") + s.inventory.slots_of_type("Cart"):
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
	for sl in display_slots() + storage_slots():
		for i in range(sl.stack.height() - 1, -1, -1):
			if sl.stack.items[i].sku_id == sku_id:
				return {"slot_id": sl.id, "index": i}
	return {}


## 为客人开一个议价。挑中的货已经不在（卖掉 / 塌了 / 被挪走 / 许给了别人）时当场重挑，没有就返回 null。
## 买过东西的客人可以「一起买」，再配一条他也看得上的。
func start_haggle(v: Dictionary) -> HaggleState:
	var pick: Dictionary = v.get("pick", {})
	var loc := locate(v["item_id"]) if v["item_id"] != "" else {}
	if pick.is_empty() or loc.is_empty() or _promised_items().has(v["item_id"]):
		pick = _pick(v)
		if pick.is_empty():
			return null
		v["pick"] = pick
		v["item_id"] = pick["item_id"]
		loc = pick
	var c: CustomerProfile = v["customer"]
	var ctx: VisitContext = v["ctx"]
	var sl: Slot = s.inventory.slots[loc["slot_id"]]
	var sku_id: String = sl.stack.items[loc["index"]].sku_id
	ctx.set_budget_from(c, pick["perceived_sku"])
	var mods := SkillSystem.haggle_mods(s.player)
	var setup := {"perceived_sku": pick["perceived_sku"], "expectation": c.expectations[int(pick["exp_index"])],
		"tol": pick["tol"], "initiative": v.get("initiative", false), "p_adj": v.get("p_adj", 0.0)}
	v["state"] = "haggling"
	var h := HaggleState.start(c, sku_id, price_of(sku_id), setup, mods, ctx, s.rng)
	if ctx.basket_count >= 1:
		var extra := _pick(v, [v["item_id"]])
		if not extra.is_empty():
			var extra_sku: String = s.inventory.slots[extra["slot_id"]].stack.items[extra["index"]].sku_id
			h.bundle_extra = {"item_id": extra["item_id"], "sku_id": extra_sku, "exp_index": extra["exp_index"],
				"reserve": HaggleState.reserve_for(c, extra["perceived_sku"], mods)}
	return h


func price_of(sku_id: String) -> float:
	return float(s.stall["prices"].get(sku_id, s.list_price(sku_id)))


## 这份货的成本价（01 §6.4）：玩家自己的账，直接读真相层的进价记录，不受技能影响。
## 没有进价记录的老货按当前本地进货价估算（店里这期没这款时取进价区间中值），estimated = true。
func cost_of(item_id: String, sku_id: String) -> Dictionary:
	for it in s.inventory.all_items():
		if it.id == item_id and it.provenance.has("unit_cost"):
			return {"cost": float(it.provenance["unit_cost"]), "estimated": false}
	for e in s.supplier_catalog:
		if e["sku_id"] == sku_id:
			return {"cost": float(e["unit_price"]), "estimated": true}
	return {"cost": float(DataDB.sku(sku_id).get("base_cost", 0.0)) * 1.175 * s.economy.price_level, "estimated": true}


## 议价结束。成交 → 客人等你拿货（waiting_item），不自动出货；没谈成 → 离开。
## 被价格吓跑计 scared_off；耐心用完走的常客回购率扣一点；嘟囔难听话会让摊前其他客人 P −0.05。
func finish(v: Dictionary, h: HaggleState) -> void:
	var ctx: VisitContext = v["ctx"]
	var c: CustomerProfile = v["customer"]
	if h != null:
		ctx.add_rapport(h.rapport_delta)
		ctx.patience_left = maxi(h.patience_left, 0)
		if h.grumbled:
			for o in visitors:
				if o != v:
					o["p_adj"] = float(o.get("p_adj", 0.0)) - 0.05
	if h == null or h.result != "deal":
		if h != null and h.result == "scared_off":
			s.period_stats["scared_off"] = int(s.period_stats.get("scared_off", 0)) + 1
		if h != null and h.ran_out:
			s.customers.penalize(c, 0.05)
		_leave(v)
		return
	v["p_final"] = h.p_final
	var want := [{"item_id": v["item_id"], "sku_id": h.sku_id, "price": h.final_price, "reserve": h.reserve,
		"exp_index": int(v["pick"].get("exp_index", 0)), "done": false}]
	if h.bundle:
		var r2 := float(h.bundle_extra["reserve"])
		var total := h.total_reserve()
		want[0]["price"] = h.final_price * h.reserve / total
		want.append({"item_id": h.bundle_extra["item_id"], "sku_id": h.bundle_extra["sku_id"],
			"price": h.final_price * r2 / total, "reserve": r2, "exp_index": int(h.bundle_extra["exp_index"]), "done": false})
	v["want"] = want
	v["hint"] = _describe_want(want)
	v["state"] = "waiting_item"
	v["wait"] = wait_for_item(c)
	v["wait_total"] = v["wait"]
	v["wait_marks"] = 0


## 等货时间：约 20 + 40·patience 秒，口才 Lv5 减缓。
func wait_for_item(c: CustomerProfile) -> float:
	return (20.0 + 40.0 * c.patience) * (1.25 if s.player.skill_level("eloquence") >= 5 else 1.0)


## 他指货那一刻你看到的：在哪一格、从上往下第几份、露出的边是什么颜色（认知层，不跟着货走）。
func _describe_want(want: Array) -> String:
	var parts: Array = []
	var a := DataDB.attributes()
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
			parts.append("%s 从上往下第 %d 份，露出%s边的那条" % [slot_title(sl), sl.stack.count_above(loc["index"]) + 1, color])
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
		var fed_up := ctx.lower_mood(WRONG_MOOD_STEP)
		if ctx.wrong_deliveries >= 2:
			_lose_deal(v, 0.15)
			_leave(v)
			out["result"] = "wrong_left"
		elif fed_up:
			_mood_leave(v)
			out["result"] = "wrong_mood_left"
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
	for w in v["want"]:
		if not ctx.done_expectations.has(w["exp_index"]):
			ctx.done_expectations.append(w["exp_index"])
	v["want"] = []
	# 交齐了：可能拿剩下的预期值再逛一轮（06 §3.5），耐心恢复一半；否则走人
	if s.rng.chance(ctx.again_p(c, float(v["p_final"]))):
		ctx.patience_left += (c.patience_n - ctx.patience_left) / 2
		v["item_id"] = ""
		v["pick"] = {}
		v["state"] = "browsing"
		v["wait"] = browse_time(c)
		out["continued"] = true
	else:
		_leave(v)
	return out


## 再问一次的不耐烦概率（06 §3.6）：精算、不随和、不沉稳的人更烦；口才 Lv3 起 ×0.7。
func p_annoy(c: CustomerProfile) -> float:
	var p := clampf(0.2 + 0.4 * c.trait_of("shrewd") - 0.25 * c.trait_of("agreeable") + 0.15 * (1.0 - c.trait_of("composed")), 0.05, 0.8)
	return p * (0.7 if s.player.skill_level("eloquence") >= 3 else 1.0)


## 等货的客人被点到、手上 / 车上没货：再问一次他要什么（06 §3.6），耗 REASK_SECONDS（时间由场景花）。
## 他按成交那一刻的描述重说一遍；第一次免费，之后按 p_annoy 掷：中 → 心情 −0.25、好感 −0.1、剩余等待 ×0.8，
## 心情掉到底就走。返回 {result: reask | reask_annoyed | reask_left | not_waiting, hint, remembered}；
## remembered 是他要的货里【强化记忆】记得所在格子的那几份（场景用来加亮）。
func reask(v: Dictionary) -> Dictionary:
	var out := {"result": "not_waiting", "hint": "", "remembered": []}
	if v["state"] != "waiting_item":
		return out
	var c: CustomerProfile = v["customer"]
	var ctx: VisitContext = v["ctx"]
	ctx.reask_count += 1
	out["hint"] = v["hint"]
	for w in v["want"]:
		var loc := locate(w["item_id"])
		if not w["done"] and not loc.is_empty() and s.knowledge.memory_of(loc["slot_id"]) != null:
			out["remembered"].append(w["item_id"])
	out["result"] = "reask"
	if ctx.reask_count > 1 and s.rng.chance(p_annoy(c)):
		ctx.add_rapport(-0.1)
		v["wait"] = float(v["wait"]) * 0.8
		out["result"] = "reask_annoyed"
		if ctx.lower_mood(REASK_MOOD_STEP):
			_mood_leave(v)
			out["result"] = "reask_left"
	return out


## 摊位（含地上）、手上（含手推车的散货篓）、行囊里一共还有几份货。
func goods_left() -> int:
	var n := 0
	for sl in display_slots() + storage_slots() + s.inventory.slots_of_type("Hand") + s.inventory.slots_of_type("Cart"):
		n += sl.stack.height() + sl.stack.collapsed_pile.size()
	return n


func table_empty() -> bool:
	for sl in display_slots():
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
