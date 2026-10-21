class_name CustomerProfile
extends RefCounted
## 真相层：客人画像（01 §4.3）。玩家永远不能直接读取，只能经【客人观察】采样。

const STRATEGIES := ["direct_discount", "fake_leave", "tug_of_war"]

var id: String
var kind: String = "retail"
var is_regular: bool = false
## 偏好：{color, pattern, material} 各一个最想要的值
var preference: Dictionary = {}
## 预算倍率：心理价 = base_price × budget_mult × 匹配度修正
var budget_mult: float = 1.0
var haggle_strategy: String = "direct_discount"
var patience: float = 0.6
var intent: float = 0.5
var hesitation: float = 0.3
var kindness: float = 0.5
var careless: float = 0.3
## 先天回购倾向（客人观察 Lv5 可见）
var loyalty_base: float = 0.3
var visits: int = 0


static func generate(id_: String, econ: Dictionary, trend: Dictionary, rng: GameRng) -> CustomerProfile:
	var c := CustomerProfile.new()
	c.id = id_
	c.preference = {
		"color": rng.weighted_pick(trend["color"]),
		"pattern": rng.weighted_pick(trend["pattern"]),
		"material": rng.weighted_pick(econ["material_pref"]),
	}
	c.budget_mult = float(econ["consumption_level"]) * exp(rng.randfn(0.0, 0.18))
	c.haggle_strategy = rng.pick(STRATEGIES)
	c.patience = clampf(rng.randfn(0.6, 0.2), 0.1, 1.0)
	c.intent = clampf(rng.randfn(0.5, 0.2), 0.05, 1.0)
	c.hesitation = clampf(rng.randfn(0.3, 0.2), 0.0, 1.0)
	c.kindness = rng.randf()
	c.careless = clampf(rng.randfn(0.3, 0.2), 0.0, 1.0)
	c.loyalty_base = clampf(rng.randfn(0.35, 0.2), 0.0, 1.0)
	return c


## 与某 SKU 的偏好匹配度 0..1。
func match_score(sku_id: String) -> float:
	var s := DataDB.sku(sku_id)
	if s.is_empty():
		return 0.0
	var m := 0.0
	m += 0.4 if s["color"] == preference.get("color") else 0.0
	m += 0.3 if s["pattern"] == preference.get("pattern") else (0.12 if s["pattern"] == "solid" else 0.0)
	m += 0.3 if s["material"] == preference.get("material") else 0.0
	return m


## 心理价（最高接受价）。match_tolerance 为口才 Lv4 等带来的"放宽条件"。
func reserve_price(sku_id: String, match_tolerance: float = 0.0) -> float:
	var s := DataDB.sku(sku_id)
	if s.is_empty():
		return 0.0
	var m := clampf(match_score(sku_id) + match_tolerance, 0.0, 1.0)
	return float(s["base_price"]) * budget_mult * lerpf(0.55, 1.15, m)


## 拿货 / 抽货时的执行者画像（03 §5）。
func to_actor_profile() -> Dictionary:
	return {"careless": careless, "patience": patience, "first_visit": visits == 0 and not is_regular, "skill": 0.0}


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "is_regular": is_regular, "preference": preference.duplicate(),
		"budget_mult": budget_mult, "haggle_strategy": haggle_strategy, "patience": patience,
		"intent": intent, "hesitation": hesitation, "kindness": kindness, "careless": careless,
		"loyalty_base": loyalty_base, "visits": visits,
	}


static func from_dict(d: Dictionary) -> CustomerProfile:
	var c := CustomerProfile.new()
	c.id = str(d.get("id", ""))
	c.kind = str(d.get("kind", "retail"))
	c.is_regular = bool(d.get("is_regular", false))
	c.preference = d.get("preference", {})
	c.budget_mult = float(d.get("budget_mult", 1.0))
	c.haggle_strategy = str(d.get("haggle_strategy", "direct_discount"))
	c.patience = float(d.get("patience", 0.6))
	c.intent = float(d.get("intent", 0.5))
	c.hesitation = float(d.get("hesitation", 0.3))
	c.kindness = float(d.get("kindness", 0.5))
	c.careless = float(d.get("careless", 0.3))
	c.loyalty_base = float(d.get("loyalty_base", 0.3))
	c.visits = int(d.get("visits", 0))
	return c
