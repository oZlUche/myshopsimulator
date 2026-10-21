class_name HaggleState
extends RefCounted
## 议价状态（06 §3.3–§3.4）。核心是成交可能性 P（可超过 1）：
## P = P0(当前差值, 容差) + 报价 / 策略失败等累计的增减。玩家用三个策略缩小货与预期的差值把 P 推高，
## 用报价踩进浮动心理价 R_float = R · P · (1 + ρ·好感) · (1 − δ·g(件数))，两条路都能成交。
## 耐心是次数：玩家每出一次手 −1，客人每还一次价 −1。
## 结果：ongoing / deal / walked_away（谈崩或耐心用完）/ scared_off（P 掉到 0 以下，被价格吓跑）。

## 策略：维度 → 按钮文字（06 §3.4）
const STRATEGIES := {
	"material": "保证品质",
	"color": "宣传颜色",
	"pattern": "展现图案",
}
const STRATEGY_LINES := {
	"material": "这料子您摸摸看，正经货。",
	"color": "这颜色衬您，今年就流行这个。",
	"pattern": "您看这花纹展开是这样的。",
}
## 中止选项
const OPTIONS := {
	"suggest_other": "那您看看别的",
}
## 连续购物时多出的选项（basket_count ≥ 1）：再拿一条，两条报一个总价（01 §6.4）
const BUNDLE_LINE := "一起买给您算便宜"

var customer: CustomerProfile
## 真货
var sku_id: String
## 客人以为的货（图案、材质从外面可能看错，06 §2）
var perceived_sku: String
var asking_price: float
## 心理价 R（按他以为的货算）
var reserve: float
## 他拿来比的那条预期值
var expectation: Dictionary = {}
## 当前三个维度的差值（策略会缩小它）
var d_dims: Dictionary = {}
var tol: float = 0.38
## 报价、策略失败等对 P 的累计增减（策略成功重算 P0 时保留）
var adj: float = 0.0
## 客人当前还价 O；0 = 还没开过价（被动客人先问"多少钱"）
var customer_offer: float = 0.0
## 玩家最近一次报价 Q；0 = 还没报过
var last_quote: float = 0.0
var patience_left: int = 6
var strategies_used: Dictionary = {}
var result: String = "ongoing"
var final_price: float = 0.0
## 成交那一刻的 P（再逛概率用，06 §3.5）
var p_final: float = 0.0
var last_line: String = ""
## 这次议价让好感变了多少（交给 VisitContext）
var rapport_delta: float = 0.0
## 耐心用完时嘟囔了难听话（摊前其他客人 P −0.05）
var grumbled := false
## 是不是耐心用完走的（常客回购率扣一点）
var ran_out := false
## 一起买的那一条：{item_id, sku_id, reserve}；为空表示不能一起买
var bundle_extra: Dictionary = {}
## 是否按"一起买"成交（final_price 是两条的总价）
var bundle := false

var ctx: VisitContext
## 口才（02 §2.6 → 06 §3.4）
var eloquence: int = 0
var fail_penalty: float = 0.05
var free_every: int = 0
var _actions := 0


## setup: {perceived_sku, expectation, d_dims, tol, initiative}；mods 见 SkillSystem.haggle_mods。
static func start(c: CustomerProfile, sku: String, asking: float, setup: Dictionary = {}, mods: Dictionary = {}, visit: VisitContext = null, rng: GameRng = null) -> HaggleState:
	var h := HaggleState.new()
	h.customer = c
	h.sku_id = sku
	h.perceived_sku = str(setup.get("perceived_sku", sku))
	h.asking_price = asking
	h.ctx = visit
	h.expectation = setup.get("expectation", c.expectations[0] if not c.expectations.is_empty() else {})
	h.tol = float(setup.get("tol", c.tolerance))
	h.d_dims = setup.get("d_dims", {}).duplicate()
	if h.d_dims.is_empty() and not h.expectation.is_empty():
		h.d_dims = dims_between(h.perceived_sku, h.expectation)
	h.reserve = reserve_for(c, h.perceived_sku, mods)
	h.eloquence = int(mods.get("eloquence", 0))
	h.fail_penalty = float(mods.get("fail_penalty", 0.05))
	h.free_every = int(mods.get("free_every", 0))
	h.patience_left = visit.patience_left if visit != null and visit.patience_left > 0 else c.patience_n
	h.adj = float(setup.get("p_adj", 0.0))
	if setup.get("initiative", false):
		# 主动：直接开价。诚实的报得接近心理价，算计的故意压低（06 §3.3）
		var anchor := 0.9
		if rng != null:
			anchor = rng.randf_range(0.85, 1.0) if c.candor >= 0.6 else rng.randf_range(0.55, 0.75)
		h.customer_offer = minf(h.reserve * anchor, asking)
		h.last_line = ("买两条了，便宜点吧，%d 块卖不卖？" if h._bulk() else "%d 块卖不卖？") % roundi(h.customer_offer)
	else:
		h.last_line = "这条多少钱？"
	return h


## 客人对这款的心理价 R：接近程度 × 预算，口才 Lv4 放宽、吆喝 Lv4 抬价。
static func reserve_for(c: CustomerProfile, sku: String, mods: Dictionary = {}) -> float:
	return c.reserve_price(sku, float(mods.get("tol_add", 0.0))) * float(mods.get("reserve_mult", 1.0))


## 一份货与一条预期值在三个维度上的差值。
static func dims_between(sku: String, e: Dictionary) -> Dictionary:
	var s := DataDB.sku(sku)
	return {
		"color": AttrDistance.color(s["color"], e["color"]),
		"material": AttrDistance.material(s["material"], e["material"]),
		"pattern": AttrDistance.pattern(s["pattern"], e["pattern"]),
	}


func distance() -> float:
	var w: Dictionary = expectation.get("weight", CustomerProfile.DEFAULT_WEIGHT)
	var d := 0.0
	for k in d_dims:
		d += float(w.get(k, 0.0)) * float(d_dims[k])
	return d


## 成交可能性 P。
func p() -> float:
	return AttrDistance.initial_p(distance(), tol) + adj


## 浮动心理价 R_float = R · P · 好感与件数修正（不超过剩余预算）。
func r_float() -> float:
	var r := reserve
	if ctx != null:
		r = ctx.drift_reserve(customer, reserve)
	return r * p()


func _bulk() -> bool:
	return ctx != null and ctx.wants_bulk_discount(customer)


## 玩家出手一次（策略 / 报价 / 一起买）。耐心已经用完 → 他走了，返回 false。
func _player_action(rng: GameRng) -> bool:
	if patience_left <= 0:
		_walk(rng)
		return false
	_actions += 1
	if free_every <= 0 or _actions % free_every != 0:
		patience_left -= 1
	return true


## 玩家报一个价格 Q。
func offer_price(price: float, rng: GameRng) -> void:
	if result != "ongoing" or not _player_action(rng):
		return
	var delta := (price - reserve) / maxf(reserve, 0.01)
	if last_quote <= 0.0:
		# 第一口价很关键：报高了直接掉，报在心理价以下给点好感（06 §3.3）
		adj += -1.2 * maxf(0.0, delta) + 0.4 * maxf(0.0, -delta)
	elif delta > 0.0:
		adj -= 0.3 * delta
	last_quote = price
	if _scared():
		return
	if _try_deal(price):
		return
	_counter(rng)


## 用一个策略（color / material / pattern），每个维度对同一份货只能用一次。
func use_strategy(dim: String, rng: GameRng) -> void:
	if result != "ongoing" or strategies_used.has(dim) or not d_dims.has(dim):
		return
	if not _player_action(rng):
		return
	strategies_used[dim] = true
	# 真话还是吹嘘由真相层决定：真货在这个维度上比他看到的更接近预期 → 真话
	var d_true := float(dims_between(sku_id, expectation)[dim])
	var d_seen := float(d_dims[dim])
	var bonus := 0.0
	if d_true < d_seen - 0.001:
		bonus = 0.3
	elif d_true > d_seen + 0.001:
		bonus = -0.2
	var fastidious := customer.trait_of("fastidious")
	var s := 0.5 + 0.08 * eloquence - 0.3 * fastidious + bonus
	if rng.chance(s):
		d_dims[dim] = d_true if bonus > 0.0 else d_seen * (1.0 - 0.5 * (1.0 - 0.5 * fastidious))
		last_line = "嗯……还真是。"
	else:
		adj -= fail_penalty
		if bonus < 0.0 and rng.chance(customer.trait_of("shrewd")):
			# 吹嘘被识破
			adj -= 0.15
			rapport_delta -= 0.2
			last_line = "你别忽悠我了。"
		else:
			last_line = "我看不怎么样。"
	if _scared():
		return
	if _try_deal(last_quote if last_quote > 0.0 else asking_price):
		return
	_counter(rng)


func choose_option(option_id: String, _rng: GameRng) -> void:
	if result != "ongoing":
		return
	if option_id == "suggest_other":
		rapport_delta -= 0.1
		result = "walked_away"
		last_line = "那我再看看。"


## "就按他说的卖"：随时可以按客人当前还价成交。
func accept_customer_offer() -> void:
	if result == "ongoing" and customer_offer > 0.0:
		rapport_delta += 0.08
		_deal(customer_offer, "好嘞！")


func bundle_available() -> bool:
	return result == "ongoing" and not bundle_extra.is_empty()


## 「一起买给您算便宜」：这一条加上 bundle_extra 那一条报一个总价。谈不拢多扣一次耐心。
func offer_bundle(total: float, rng: GameRng) -> void:
	if not bundle_available() or not _player_action(rng):
		return
	var extra := float(bundle_extra["reserve"])
	if ctx != null:
		extra = ctx.drift_reserve(customer, extra)
	var both := r_float() + extra * p()
	if p() >= 1.0 or total <= both:
		bundle = true
		rapport_delta += 0.05
		_deal(total, "两条一起，行！")
		return
	adj -= 0.05
	patience_left -= 1
	last_line = "两条 %d 还是贵了。" % roundi(total)
	if _scared():
		return
	_counter(rng)


## 成交条件（06 §3.4）：P ≥ 1 按 Q 成交；Q ≤ R_float 按 Q 成交；Q 不高于他自己的还价也成交。
func _try_deal(q: float) -> bool:
	if p() >= 1.0 or q <= r_float() or (customer_offer > 0.0 and q <= customer_offer):
		_deal(q, "行，就这个价。" if p() >= 1.0 else "好，成交。")
		return true
	return false


## P 掉到 0 以下：被价格吓跑。
func _scared() -> bool:
	if p() > 0.0:
		return false
	result = "scared_off"
	rapport_delta -= 0.1
	last_line = "这么贵？算了。"
	return true


## 客人还价：O 向浮动心理价靠一步，耗一次耐心。
func _counter(rng: GameRng) -> void:
	var target := r_float()
	if customer_offer <= 0.0:
		var anchor := rng.randf_range(0.85, 1.0) if customer.candor >= 0.6 else rng.randf_range(0.55, 0.75)
		customer_offer = target * anchor
	else:
		# 客人出过的价只往上走：心里价掉到他已出的价以下（招数失败、被吓到）时咬住原价不松口，但不往回缩
		customer_offer += maxf(0.0, target - customer_offer) * (0.35 + 0.3 * customer.trait_of("agreeable"))
	if last_quote > 0.0:
		customer_offer = minf(customer_offer, last_quote)
	customer_offer = maxf(1.0, customer_offer)
	patience_left -= 1
	var o := roundi(customer_offer)
	if patience_left <= 0:
		last_line = "就 %d，不行我走了。" % o
	elif _bulk():
		last_line = "买两条了，便宜点吧，%d。" % o
	else:
		match customer.haggle_strategy:
			"fake_leave":
				last_line = "太贵了，我去别家看看……（作势要走）%d 吧。" % o if rng.chance(0.5) else "%d，行就拿。" % o
			"direct_discount":
				last_line = "再便宜点，%d。" % o
			_:
				last_line = "%d，你再让让。" % o


## 耐心用完：按脾气掷一次，嘟囔难听话还是默默走（06 §3.4）。
func _walk(rng: GameRng) -> void:
	result = "walked_away"
	ran_out = true
	if rng.chance(customer.temper):
		grumbled = true
		rapport_delta -= 0.3
		last_line = "什么摊子，磨半天！"
	else:
		rapport_delta -= 0.1
		last_line = "算了算了，不买了。"


## 心理价（一起买时为两条之和）。
func total_reserve() -> float:
	return reserve + (float(bundle_extra["reserve"]) if bundle else 0.0)


func _deal(price: float, line: String) -> void:
	result = "deal"
	final_price = price
	p_final = p()
	last_line = line
	# 不超过心理价 → 好感升（越便宜越高兴）；超过就是被宰了
	var ratio := price / maxf(total_reserve(), 0.01)
	rapport_delta += 0.1 + 0.2 * maxf(0.0, 1.0 - ratio) - 1.0 * maxf(0.0, ratio - 1.0)
