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
## 当前逗留的客人 [{customer, item_id, state, wait}]
## state: browsing 在看 → asking 在问价（等玩家理会）→ haggling 议价中 → left
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
			_leave(v)
		elif v["state"] == "browsing" and s.rng.chance(v["customer"].intent * (1.0 - 0.5 * v["customer"].hesitation) * 0.04 * dt):
			# 犹豫一会儿后开口问价
			v["state"] = "asking"
			v["wait"] = 15.0 + 45.0 * v["customer"].patience


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
		"customer": c, "item_id": best["item_id"],
		"state": "asking" if wants_to_ask else "browsing",
		"wait": 20.0 + 60.0 * c.patience,
	}
	visitors.append(v)
	visitor_arrived.emit(v)


## 客人在摊位上最想要的那份货。客人只看得到边缘条，按偏好匹配挑。
func _best_item_for(c: CustomerProfile) -> Dictionary:
	var best := {}
	for sl in s.inventory.slots_of_type("StallTable"):
		for i in sl.stack.height():
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


## 为客人开一个议价。看中的货已经不在（卖掉 / 塌了 / 被挪走）时换一份，没有就返回 null。
func start_haggle(v: Dictionary) -> HaggleState:
	var loc := locate(v["item_id"])
	if loc.is_empty():
		var best := _best_item_for(v["customer"])
		if best.is_empty():
			return null
		v["item_id"] = best["item_id"]
		loc = best
	var sl: Slot = s.inventory.slots[loc["slot_id"]]
	var sku_id: String = sl.stack.items[loc["index"]].sku_id
	var asking := float(s.stall["prices"].get(sku_id, DataDB.sku(sku_id)["base_price"]))
	v["state"] = "haggling"
	return HaggleState.start(v["customer"], sku_id, asking, SkillSystem.haggle_mods(s.player))


## 议价结束：成交则从摊位取出那份货卖掉（下层货要过抽取结算），客人离开。
func finish(v: Dictionary, h: HaggleState, pull_input: Dictionary = ActionAPI.CAREFUL_PULL) -> Dictionary:
	var out := {"ok": false}
	if h != null and h.result == "deal":
		var loc := locate(v["item_id"])
		if not loc.is_empty():
			out = api.sell(loc["slot_id"], loc["index"], h.final_price, h.customer, h.reserve, pull_input)
	_leave(v)
	return out
