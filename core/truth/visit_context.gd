class_name VisitContext
extends RefCounted
## 真相层：同次购物上下文（01 §4.3）。客人在摊前从来到走，买了几件、花了多少、对你印象如何。
## 客人离开即销毁，不进存档。

## 一次逛摊的总预算按"几件他第一眼看中的那款"算
const BUDGET_ITEMS := 3.0

var basket_count: int = 0
var spent: float = 0.0
## 本次好感 −1..1：成交价不超过他的心理价、议价客气 → 升；被怼、被宰、递错货 → 降
var rapport: float = 0.0
var wrong_deliveries: int = 0
## 本次逛摊的总预算（元），第一次问价时按那款的基准价定
var budget: float = 0.0
## 剩余耐心：议价消耗，成交交货后部分恢复
var patience: float = 0.6


static func create(c: CustomerProfile) -> VisitContext:
	var ctx := VisitContext.new()
	ctx.patience = c.patience
	return ctx


func set_budget_from(c: CustomerProfile, sku_id: String) -> void:
	if budget <= 0.0:
		budget = c.budget_mult * BUDGET_ITEMS * float(DataDB.sku(sku_id).get("base_price", 0.0))


func add_rapport(d: float) -> void:
	rapport = clampf(rapport + d, -1.0, 1.0)


func budget_left() -> float:
	return maxf(0.0, budget - spent)


## 剩余预算占比 0..1（f_budget）。
func budget_ratio() -> float:
	return clampf(budget_left() / budget, 0.0, 1.0) if budget > 0.0 else 1.0


## ρ：熟了、好说话 → 给个好价（心理价上浮）。
static func rho(c: CustomerProfile) -> float:
	return 0.05 + 0.15 * c.kindness + 0.1 * minf(float(c.visits), 6.0) / 6.0


## δ：爱砍价、不好说话 → 买多要优惠（心理价下压）。
static func delta(c: CustomerProfile) -> float:
	return 0.04 + 0.12 * (1.0 - c.kindness) + (0.1 if c.haggle_strategy == "direct_discount" else 0.0)


## 随件数递增、趋于饱和：0 件 0，1 件 ≈0.49，2 件 ≈0.74，… → 1。
static func g(n: int) -> float:
	return 1.0 - exp(-0.67 * n)


## 下一件的心理价：reserve' = reserve_base × (1 + ρ·rapport) × (1 − δ·g(basket_count))，不超过剩余预算。
func drift_reserve(c: CustomerProfile, reserve_base: float) -> float:
	var r := reserve_base * (1.0 + rho(c) * rapport) * (1.0 - delta(c) * g(basket_count))
	return minf(r, budget_left()) if budget > 0.0 else r


## 熟了好说话的客人：成交门槛放宽一点。
func accept_bonus(c: CustomerProfile) -> float:
	return 0.15 * rho(c) * maxf(rapport, 0.0)


## 熟了好说话的客人：开口价离心理价更近，少磨几轮。
func anchor_bonus(c: CustomerProfile) -> float:
	return 0.4 * rho(c) * maxf(rapport, 0.0)


## 买过以后会不会要求"买两条便宜点"。
func wants_bulk_discount(c: CustomerProfile) -> bool:
	return basket_count >= 1 and delta(c) * g(basket_count) > rho(c) * maxf(rapport, 0.0)


## 交货后继续逛的概率：intent × f_budget × (0.5 + 0.5·rapport) × (1 − 0.3·hesitation)，常客额外 +。
func continue_p(c: CustomerProfile) -> float:
	var p := c.intent * budget_ratio() * (0.5 + 0.5 * rapport) * (1.0 - 0.3 * c.hesitation)
	if c.is_regular:
		p += 0.1
	return clampf(p, 0.0, 0.95)
