class_name CustomerRegistry
extends RefCounted
## 常客与回购率（01 §4.3、02 §2.3）。常客跨旬持久存在；过路客一次性生成、不入表。

var regulars: Dictionary = {}           # {id: CustomerProfile}
var return_probability: Dictionary = {} # {id: float}
var _next_id := 1


func new_customer_id() -> String:
	var id := "cu_%06d" % _next_id
	_next_id += 1
	return id


## 成交后按 (实付 − 心理价)/心理价 调整回购率；宰客短期赚钱、长期流失。
## 首次成交的过路客以 loyalty_base 为起点被登记为常客候选。
func record_purchase(c: CustomerProfile, paid: float, reserve: float, loyalty_bonus: float = 0.0) -> void:
	c.visits += 1
	var overcharge := (paid - reserve) / maxf(reserve, 0.01)
	if not regulars.has(c.id):
		c.is_regular = true
		regulars[c.id] = c
		return_probability[c.id] = c.loyalty_base
	var p: float = return_probability[c.id]
	p += -0.6 * maxf(overcharge, -0.3) + loyalty_bonus
	return_probability[c.id] = clampf(p, 0.0, 0.95)


## 本旬会回来的常客列表。
func roll_returning(rng: GameRng) -> Array[CustomerProfile]:
	var out: Array[CustomerProfile] = []
	for id in regulars:
		if rng.chance(float(return_probability.get(id, 0.0))):
			out.append(regulars[id])
	return out


func to_dict() -> Dictionary:
	var r := {}
	for id in regulars:
		r[id] = regulars[id].to_dict()
	return {"regulars": r, "return_probability": return_probability.duplicate(), "next_id": _next_id}


static func from_dict(d: Dictionary) -> CustomerRegistry:
	var reg := CustomerRegistry.new()
	var r: Dictionary = d.get("regulars", {})
	for id in r:
		reg.regulars[id] = CustomerProfile.from_dict(r[id])
	var rp: Dictionary = d.get("return_probability", {})
	for id in rp:
		reg.return_probability[id] = float(rp[id])
	reg._next_id = int(d.get("next_id", 1))
	return reg
