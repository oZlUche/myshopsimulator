class_name HaggleState
extends RefCounted
## 议价状态（01 §6.4）。对话选项与自由输入价格走同一个状态，保证以后增删选项不影响数值。
## 结果：ongoing / deal / walked_away。

const OPTIONS := {
	"firm": "这是最低价了",
	"suggest_other": "那您看看别的",
}

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


static func start(c: CustomerProfile, sku: String, asking: float, mods: Dictionary = {}) -> HaggleState:
	var h := HaggleState.new()
	h.customer = c
	h.sku_id = sku
	h.asking_price = asking
	h.reserve = c.reserve_price(sku, float(mods.get("match_tolerance", 0.0))) * float(mods.get("reserve_mult", 1.0))
	h.accept_tolerance = float(mods.get("accept_tolerance", 0.0))
	h.patience_loss_mult = float(mods.get("patience_loss_mult", 1.0))
	h.patience_left = c.patience
	var anchor := {"direct_discount": 0.7, "fake_leave": 0.6, "tug_of_war": 0.55}.get(c.haggle_strategy, 0.65) as float
	h.customer_offer = minf(h.reserve * anchor, asking)
	h.last_line = "%d 块卖不卖？" % roundi(h.customer_offer)
	return h


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
				_lose_patience(0.25)
				if result == "ongoing":
					last_line = "这么硬啊……%d 真不行？" % roundi(customer_offer)
		"suggest_other":
			result = "walked_away"
			last_line = "那我再看看。"


func accept_customer_offer() -> void:
	if result == "ongoing":
		_deal(customer_offer, "好嘞！")


func _lose_patience(amount: float) -> void:
	patience_left -= amount * patience_loss_mult
	if patience_left <= 0.0:
		result = "walked_away"
		last_line = "算了算了，不买了。"


func _deal(price: float, line: String) -> void:
	result = "deal"
	final_price = price
	last_line = line
