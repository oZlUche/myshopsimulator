class_name VisitContext
extends RefCounted
## 真相层：同次购物上下文（01 §4.3、06 §3.5）。客人在摊前从来到走，买了几件、花了多少、对你印象如何。
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
## 剩余耐心次数：议价消耗，成交交货后恢复一半；−1 = 还没讲过价
var patience_left: int = -1
## 这次来摊的容差随机偏移（±0.05，06 §2）
var tol_offset: float = 0.0
## 已经买到的预期值序号
var done_expectations: Array = []
## 本次来访的心情（06 §3.6）：从 mood_today（−0.2..0.2）起算，被再问、被递错、等太久都往下走，不回升；
## 掉到 MOOD_LEAVE 以下就「算了，不要了」走人
var mood: float = 0.0
## 等货时被再问了几次，第 1 次免费
var reask_count: int = 0

const MOOD_LEAVE := -0.5


static func create(_c: CustomerProfile, rng: GameRng = null) -> VisitContext:
	var ctx := VisitContext.new()
	if rng != null:
		ctx.tol_offset = rng.randf_range(-0.05, 0.05)
		ctx.mood = rng.randf_range(-0.2, 0.2)
	return ctx


## 心情只降不升（06 §3.6）。返回是不是已经低到要走。
func lower_mood(d: float) -> bool:
	mood -= absf(d)
	return mood < MOOD_LEAVE


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


## 这次来摊的挑选容差：派生容差 + 来摊偏移 + 口才 Lv4 放宽。
func tolerance(c: CustomerProfile, tol_add: float = 0.0) -> float:
	return maxf(0.05, c.tolerance + tol_offset + tol_add)


## 还没买到的预期值序号（按优先级）。
func remaining_expectations(c: CustomerProfile) -> Array:
	var out: Array = []
	for i in c.expectations.size():
		if not done_expectations.has(i):
			out.append(i)
	return out


## ρ：熟了、随和 → 给个好价（心理价上浮）。
static func rho(c: CustomerProfile) -> float:
	return 0.05 + 0.15 * c.trait_of("agreeable") + 0.1 * minf(float(c.visits), 6.0) / 6.0


## δ：精算、爱直接砍价 → 买多要优惠（心理价下压）。
static func delta(c: CustomerProfile) -> float:
	return 0.04 + 0.12 * c.trait_of("shrewd") + (0.1 if c.haggle_strategy == "direct_discount" else 0.0)


## 随件数递增、趋于饱和：0 件 0，1 件 ≈0.49，2 件 ≈0.74，… → 1。
static func g(n: int) -> float:
	return 1.0 - exp(-0.67 * n)


## 好感与件数修正后的心理价：reserve_base × (1 + ρ·rapport) × (1 − δ·g(basket_count))，不超过剩余预算。
## 浮动心理价 R_float 再乘成交可能性 P（HaggleState.r_float）。
func drift_reserve(c: CustomerProfile, reserve_base: float) -> float:
	var r := reserve_base * (1.0 + rho(c) * rapport) * (1.0 - delta(c) * g(basket_count))
	return minf(r, budget_left()) if budget > 0.0 else r


## 买过以后会不会要求"买两条便宜点"。
func wants_bulk_discount(c: CustomerProfile) -> bool:
	return basket_count >= 1 and delta(c) * g(basket_count) > rho(c) * maxf(rapport, 0.0)


## 交货后再逛的概率（06 §3.5）：
## clamp(P_final, 0, 1) · (0.4 + 0.4·外向 + 0.2·intent − 0.3·hesitation) · [还有没买到的预期] · f_budget。
func again_p(c: CustomerProfile, p_final: float) -> float:
	if remaining_expectations(c).is_empty():
		return 0.0
	var p := clampf(p_final, 0.0, 1.0) * (0.4 + 0.4 * c.trait_of("sociable") + 0.2 * c.intent - 0.3 * c.hesitation) * budget_ratio()
	return clampf(p, 0.0, 0.95)
