extends RefCounted
## 1 → 2：客人性格改为五维潜在向量 + 派生参数（06 §1.4 方案 C），偏好改为预期值列表。
## 只做纯字典变换（不引用游戏类）。旧字段原样保留，读档时 CustomerProfile.from_dict 只读新字段：
## - 性格向量按旧字段反推：patience → composed，kindness → agreeable，haggle_strategy → shrewd；
##   外向、挑剔按这三维最接近的原型补（原型数值抄自 2026-10-21 的 data/personality_map.json，此后不随表变）。
## - 能直接沿用的旧值写进 derived（kindness、hesitation、intent、loyalty_base、haggle_strategy），其余读档时按向量补齐。
## - preference → expectations[0]（权重取默认 0.4 / 0.3 / 0.3）。
## - period_stats.undelivered 改名 lost_after_deal。

## [sociable, shrewd, composed, fastidious, agreeable]
const ARCHETYPES := {
	"shrewd_auntie": [0.7, 0.85, 0.5, 0.5, 0.4],
	"shy_student": [0.2, 0.3, 0.4, 0.35, 0.65],
	"easygoing_guy": [0.8, 0.25, 0.45, 0.2, 0.75],
	"picky_officeworker": [0.4, 0.55, 0.3, 0.85, 0.35],
	"leisurely_elder": [0.45, 0.4, 0.85, 0.45, 0.7],
}
const SHREWD_OF := {"direct_discount": 0.75, "fake_leave": 0.55, "tug_of_war": 0.45}


func migrate(d: Dictionary) -> Dictionary:
	var cust: Dictionary = d.get("customers", {})
	var regs: Dictionary = cust.get("regulars", {})
	for id in regs:
		regs[id] = _customer(regs[id])
	var st: Dictionary = d.get("period_stats", {})
	if st.has("undelivered") and not st.has("lost_after_deal"):
		st["lost_after_deal"] = st["undelivered"]
	return d


func _customer(c: Dictionary) -> Dictionary:
	if c.has("personality"):
		return c
	var composed := clampf((float(c.get("patience", 0.6)) - 0.2) / 0.8, 0.0, 1.0)
	var agreeable := clampf(float(c.get("kindness", 0.5)), 0.0, 1.0)
	var shrewd := float(SHREWD_OF.get(str(c.get("haggle_strategy", "")), 0.5))
	var best := ""
	var best_d := INF
	for a in ARCHETYPES:
		var v: Array = ARCHETYPES[a]
		var dist := pow(v[1] - shrewd, 2) + pow(v[2] - composed, 2) + pow(v[4] - agreeable, 2)
		if dist < best_d:
			best_d = dist
			best = a
	var arch: Array = ARCHETYPES[best]
	c["archetype"] = best
	c["personality"] = {"sociable": arch[0], "shrewd": shrewd, "composed": composed, "fastidious": arch[3], "agreeable": agreeable}
	var derived := {}
	for k in ["kindness", "hesitation", "intent", "loyalty_base", "haggle_strategy"]:
		if c.has(k):
			derived[k] = c[k]
	c["derived"] = derived
	var pref: Dictionary = c.get("preference", {})
	if not pref.is_empty() and not c.has("expectations"):
		c["expectations"] = [{"color": pref.get("color", "red"), "material": pref.get("material", "wool"),
			"pattern": pref.get("pattern", "solid"), "weight": {"color": 0.4, "material": 0.3, "pattern": 0.3}}]
	return c
