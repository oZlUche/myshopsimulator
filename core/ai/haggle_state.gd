class_name HaggleState
extends RefCounted
## 议价状态（01 §6.4）。对话选项与自由输入价格走同一个状态，保证以后增删选项不影响数值。
## 结果：ongoing / deal / walked_away。

const OPTIONS := {
	"firm": "这是最低价了",
	"suggest_other": "那您看看别的",
}
## 连续购物时多出的选项（basket_count ≥ 1）：再拿一条，两条报一个总价（01 §6.4）
const BUNDLE_LINE := "一起买给您算便宜"

var customer: CustomerProfile
var sku_id: String
var asking_price: float
var reserve: float
## 客人当前出价（从低往上让）
var customer_offer: float
var patience_left: float
var rounds: int = 0
var result: String = "ongoing"
var final_price: float = 0.0
var last_line: String = ""
## 来自技能的修正（口才 / 吆喝）
var accept_tolerance: float = 0.0
var patience_loss_mult: float = 1.0
## 这次议价让好感变了多少（交给 VisitContext）
var rapport_delta: float = 0.0
## 一起买的那一条：{item_id, sku_id, reserve}；为空表示不能一起买
var bundle_extra: Dictionary = {}
## 是否按"一起买"成交（final_price 是两条的总价）
var bundle := false


## ctx 为同次购物上下文：心理价按好感和已买件数波动（01 §4.3），耐心接着上一件剩下的。
static func start(c: CustomerProfile, sku: String, asking: float, mods: Dictionary = {}, ctx: VisitContext = null) -> HaggleState:
	var h := HaggleState.new()
	h.customer = c
	h.sku_id = sku
	h.asking_price = asking
	h.reserve = reserve_for(c, sku, mods, ctx)
	h.accept_tolerance = float(mods.get("accept_tolerance", 0.0))
	h.patience_loss_mult = float(mods.get("patience_loss_mult", 1.0))
	h.patience_left = c.patience
	var anchor := {"direct_discount": 0.7, "fake_leave": 0.6, "tug_of_war": 0.55}.get(c.haggle_strategy, 0.65) as float
	if ctx != null:
		h.accept_tolerance += ctx.accept_bonus(c)
		anchor = minf(0.95, anchor + ctx.anchor_bonus(c))
		h.patience_left = ctx.patience
	h.customer_offer = minf(h.reserve * anchor, asking)
	if ctx != null and ctx.wants_bulk_discount(c):
		h.last_line = "买两条了，便宜点吧，%d 块卖不卖？" % roundi(h.customer_offer)
	elif ctx != null and ctx.basket_count >= 1 and ctx.rapport > 0.3:
		h.last_line = "老板人实在，这条 %d 怎么样？" % roundi(h.customer_offer)
	else:
		h.last_line = "%d 块卖不卖？" % roundi(h.customer_offer)
	return h


## 客人对这款的心理价：技能修正后的基准 × 同次购物的波动。
static func reserve_for(c: CustomerProfile, sku: String, mods: Dictionary = {}, ctx: VisitContext = null) -> float:
	var r := c.reserve_price(sku, float(mods.get("match_tolerance", 0.0))) * float(mods.get("reserve_mult", 1.0))
	return ctx.drift_reserve(c, r) if ctx != null else r


## 玩家报一个价格。
func offer_price(price: float, rng: GameRng) -> void:
	if result != "ongoing":
		return
	rounds += 1
	if price <= customer_offer:
		_deal(price, "好，成交。")
		return
	var limit := reserve * (1.0 + accept_tolerance)
	if price <= limit:
		# 低于心理价时越接近客人出价越容易成交；拉锯型客人会多磨几轮。
		var closeness := 1.0 - (price - customer_offer) / maxf(limit - customer_offer, 0.01)
		var p := 0.35 + 0.6 * closeness - (0.15 if customer.haggle_strategy == "tug_of_war" else 0.0)
		if rng.chance(p):
			_deal(price, "唉，行吧。")
			return
	_lose_patience(0.18 if price <= limit else 0.3)
	if price > limit * 1.3:
		rapport_delta -= 0.04
	if result == "ongoing":
		customer_offer = minf(customer_offer + (reserve - customer_offer) * 0.35, price)
		if customer.haggle_strategy == "fake_leave" and rng.chance(0.4):
			last_line = "太贵了，我去别家看看……（作势要走）%d 吧。" % roundi(customer_offer)
		else:
			last_line = "再便宜点，%d。" % roundi(customer_offer)


## 选一个对话选项。
func choose_option(option_id: String, rng: GameRng) -> void:
	if result != "ongoing":
		return
	rounds += 1
	match option_id:
		"firm":
			# 坚持当前要价：心理价够就有机会成交，否则掉耐心。
			if asking_price <= reserve * (1.0 + accept_tolerance) and rng.chance(0.5):
				_deal(asking_price, "行吧行吧，给你。")
			else:
				rapport_delta -= 0.08
				_lose_patience(0.25)
				if result == "ongoing":
					last_line = "这么硬啊……%d 真不行？" % roundi(customer_offer)
		"suggest_other":
			rapport_delta -= 0.1
			result = "walked_away"
			last_line = "那我再看看。"


func accept_customer_offer() -> void:
	if result == "ongoing":
		rapport_delta += 0.08
		_deal(customer_offer, "好嘞！")


func bundle_available() -> bool:
	return result == "ongoing" and not bundle_extra.is_empty()


## 「一起买给您算便宜」：这一条加上 bundle_extra 那一条报一个总价。
## 两条心理价之和是上限；谈不拢扣的耐心比单件多。
func offer_bundle(total: float, rng: GameRng) -> void:
	if not bundle_available():
		return
	rounds += 1
	var both := reserve + float(bundle_extra["reserve"])
	var limit := both * (1.0 + accept_tolerance)
	var their_offer := customer_offer * both / maxf(reserve, 0.01)
	if total <= their_offer:
		bundle = true
		rapport_delta += 0.05
		_deal(total, "两条一起，行！")
		return
	if total <= limit:
		var closeness := 1.0 - (total - their_offer) / maxf(limit - their_offer, 0.01)
		if rng.chance(0.3 + 0.6 * closeness):
			bundle = true
			rapport_delta += 0.05
			_deal(total, "两条 %d，那就都要了。" % roundi(total))
			return
	_lose_patience(0.45 if total <= limit else 0.6)
	if result == "ongoing":
		last_line = "两条 %d 还是贵了。" % roundi(total)


func _lose_patience(amount: float) -> void:
	patience_left -= amount * patience_loss_mult
	if patience_left <= 0.0:
		rapport_delta -= 0.1
		result = "walked_away"
		last_line = "算了算了，不买了。"


## 心理价（一起买时为两条之和）。
func total_reserve() -> float:
	return reserve + (float(bundle_extra["reserve"]) if bundle else 0.0)


func _deal(price: float, line: String) -> void:
	result = "deal"
	final_price = price
	last_line = line
	# 不超过心理价 → 好感升（越便宜越高兴）；超过就是被宰了
	var ratio := price / maxf(total_reserve(), 0.01)
	rapport_delta += 0.1 + 0.2 * maxf(0.0, 1.0 - ratio) - 1.0 * maxf(0.0, ratio - 1.0)
