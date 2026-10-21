class_name CustomerProfile
extends RefCounted
## 真相层：客人画像（01 §4.3、06 §1、§2、§5）。玩家永远不能直接读取，只能经【客人观察】采样。
## 性格两层：personality 五维潜在向量（隐藏）→ derived 派生行为参数（生成时一次性算好，之后只读它）。
## 预算、熟悉度（visits）不是性格，是状态。

const STRATEGIES := ["direct_discount", "fake_leave", "tug_of_war"]
const DEFAULT_WEIGHT := {"color": 0.4, "material": 0.3, "pattern": 0.3}

var id: String
var kind: String = "retail"
var is_regular: bool = false
var visits: int = 0
## 原型 id（personality_map.json 的 archetypes），调试与将来按街区调权重用
var archetype: String = ""
## {sociable, shrewd, composed, fastidious, agreeable}，0..1
var personality: Dictionary = {}
## 马虎：手上功夫，不属于性格向量（03 §5）
var careless: float = 0.3
## 派生行为参数（06 §1.4）：patience_n, crowd_pref, initiative, candor, tolerance, n_expect,
## browse_speed, temper, self_serve, hesitation, intent, kindness, loyalty_base, haggle_strategy
var derived: Dictionary = {}
## 预期值向量，按优先级排好：[{color, material, pattern, weight: {color, material, pattern}}]
var expectations: Array = []
## 预算倍率：心理价 = base_price × budget_mult × 接近程度修正。
## budget_mult = 消费能力 S · 物价 π · 个人宽裕程度 budget_noise（09 §3.3），每次来店时按当旬经济重算。
var budget_mult: float = 1.0
## 个人宽裕程度 exp(N(0, 0.18))，生成时定下，跟人走
var budget_noise: float = 1.0
## 景气对购物意向的修正 0.1·g（每次来店时按当旬经济设，不存档）
var intent_shift: float = 0.0

## 常用派生参数的直接读写（老代码和测试沿用这些名字）
var patience_n: int:
	get: return int(derived.get("patience_n", 6))
	set(v): derived["patience_n"] = v
var crowd_pref: float:
	get: return float(derived.get("crowd_pref", 0.0))
	set(v): derived["crowd_pref"] = v
var tolerance: float:
	get: return float(derived.get("tolerance", 0.38))
	set(v): derived["tolerance"] = v
var initiative: float:
	get: return float(derived.get("initiative", 0.5))
	set(v): derived["initiative"] = v
var candor: float:
	get: return float(derived.get("candor", 0.5))
	set(v): derived["candor"] = v
var browse_speed: float:
	get: return float(derived.get("browse_speed", 0.5))
	set(v): derived["browse_speed"] = v
var temper: float:
	get: return float(derived.get("temper", 0.25))
	set(v): derived["temper"] = v
var self_serve: float:
	get: return float(derived.get("self_serve", 0.3))
	set(v): derived["self_serve"] = v
## 购物意向 = 性格派生值 + 景气修正，夹到 0.05..1（派生值本身已在这个范围里）
var intent: float:
	get:
		var b := float(derived.get("intent", 0.5))
		return b if intent_shift == 0.0 else clampf(b + intent_shift, 0.05, 1.0)
	set(v): derived["intent"] = v
var hesitation: float:
	get: return float(derived.get("hesitation", 0.3))
	set(v): derived["hesitation"] = v
var kindness: float:
	get: return float(derived.get("kindness", 0.5))
	set(v): derived["kindness"] = v
var loyalty_base: float:
	get: return float(derived.get("loyalty_base", 0.3))
	set(v): derived["loyalty_base"] = v
var haggle_strategy: String:
	get: return str(derived.get("haggle_strategy", "tug_of_war"))
	set(v): derived["haggle_strategy"] = v
## 耐心折成 0..1（等人、等货的时长用）：3 次 → 0，9 次 → 1
var patience: float:
	get: return clampf((patience_n - 3) / 6.0, 0.0, 1.0)
## 第一条预期值的三个属性（客人观察 Lv1、合拍客人保底用）
var preference: Dictionary:
	get:
		if expectations.is_empty():
			return {}
		var e: Dictionary = expectations[0]
		return {"color": e["color"], "pattern": e["pattern"], "material": e["material"]}
	set(v):
		if expectations.is_empty():
			expectations.append({"weight": DEFAULT_WEIGHT.duplicate()})
		for k in ["color", "pattern", "material"]:
			if v.has(k):
				expectations[0][k] = v[k]


func trait_of(dim: String) -> float:
	return float(personality.get(dim, 0.5))


## 新客人：抽原型 → 性格向量 → 派生参数 → 预期值。archetype 为空时按权重抽。
static func generate(id_: String, econ: Dictionary, trend: Dictionary, rng: GameRng, archetype_id: String = "") -> CustomerProfile:
	var c := CustomerProfile.new()
	c.id = id_
	c.archetype = archetype_id if archetype_id != "" else Personality.pick_archetype(rng)
	c.personality = Personality.roll_vector(c.archetype, rng)
	c.derived = Personality.derive(c.personality, rng)
	c.careless = clampf(rng.randfn(0.3, 0.2), 0.0, 1.0)
	c.budget_noise = exp(rng.randfn(0.0, 0.18))
	c.apply_economy(econ)
	c.expectations = roll_expectations(int(c.derived["n_expect"]), econ, trend, rng)
	return c


## 按当旬经济定预算倍率和购物意向修正（09 §3.3）。新客人生成时、常客回来时各调一次。
func apply_economy(econ: Dictionary) -> void:
	var G := float(econ.get("G", econ.get("consumption_level", 1.0)))
	var spend := float(econ.get("spending_power", pow(G, EconomyState.SPEND_ELASTICITY)))
	budget_mult = spend * float(econ.get("price_level", 1.0)) * budget_noise
	intent_shift = 0.1 * (G - 1.0)


## 第一条按趋势 + 本季材质采样；后面几条多半是第一条换个颜色或图案，偶尔完全另起。
static func roll_expectations(n: int, econ: Dictionary, trend: Dictionary, rng: GameRng) -> Array:
	var out: Array = []
	for i in maxi(1, n):
		var e: Dictionary
		if i == 0 or rng.chance(0.25):
			e = {"color": rng.weighted_pick(trend["color"]), "pattern": rng.weighted_pick(trend["pattern"]),
				"material": rng.weighted_pick(econ["material_pref"])}
		else:
			e = (out[0] as Dictionary).duplicate()
			var dim := "color" if rng.chance(0.6) else "pattern"
			e[dim] = rng.weighted_pick(trend[dim])
		var w := {"color": 0.2 + rng.randf(), "material": 0.2 + rng.randf(), "pattern": 0.2 + rng.randf()}
		var sum := float(w["color"]) + float(w["material"]) + float(w["pattern"])
		for k in w:
			w[k] = float(w[k]) / sum
		e["weight"] = w
		out.append(e)
	return out


## 与某 SKU 的接近程度 0..1：1 − 与最接近的那条预期值的差值。
func match_score(sku_id: String) -> float:
	var best := 1.0
	for e in expectations:
		best = minf(best, AttrDistance.to_expectation(sku_id, e))
	return 1.0 - best


## 心理价 R（最高接受价的基准，06 §3.3）。tol_add 为口才 Lv4 的"放宽条件"，让差值打折。
func reserve_price(sku_id: String, tol_add: float = 0.0) -> float:
	var s := DataDB.sku(sku_id)
	if s.is_empty():
		return 0.0
	var m := clampf(match_score(sku_id) + tol_add, 0.0, 1.0)
	return float(s["base_price"]) * budget_mult * lerpf(0.55, 1.15, m)


## 拿货 / 抽货时的执行者画像（03 §5）。
func to_actor_profile() -> Dictionary:
	return {"careless": careless, "patience": patience, "first_visit": visits == 0 and not is_regular, "skill": 0.0}


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "is_regular": is_regular, "visits": visits, "archetype": archetype,
		"personality": personality.duplicate(), "careless": careless, "derived": derived.duplicate(),
		"expectations": expectations.duplicate(true), "budget_mult": budget_mult,
		"budget_noise": budget_noise,
	}


## 读档。派生参数缺项时按性格向量无噪声补齐（老存档迁移来的常客只带了一部分）。
static func from_dict(d: Dictionary) -> CustomerProfile:
	var c := CustomerProfile.new()
	c.id = str(d.get("id", ""))
	c.kind = str(d.get("kind", "retail"))
	c.is_regular = bool(d.get("is_regular", false))
	c.visits = int(d.get("visits", 0))
	c.archetype = str(d.get("archetype", ""))
	c.personality = d.get("personality", {})
	for dim in Personality.DIMS:
		c.personality[dim] = float(c.personality.get(dim, 0.5))
	c.careless = float(d.get("careless", 0.3))
	var full := Personality.derive(c.personality)
	var saved: Dictionary = d.get("derived", {})
	for k in full:
		c.derived[k] = saved.get(k, full[k])
	for k in saved:
		c.derived[k] = saved[k]
	c.expectations = d.get("expectations", [])
	for e in c.expectations:
		if not e.has("weight"):
			e["weight"] = DEFAULT_WEIGHT.duplicate()
	c.budget_mult = float(d.get("budget_mult", 1.0))
	# 老存档的预算倍率 = 消费水平 × 个人噪声，消费水平当时在 1 附近，直接当个人噪声用
	c.budget_noise = float(d.get("budget_noise", c.budget_mult))
	return c
