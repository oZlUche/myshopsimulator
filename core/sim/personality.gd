class_name Personality
extends RefCounted
## 客人（以及以后员工）的性格（06 §1.4 方案 C）：五维潜在向量 → 派生行为参数。
## 映射表在 data/personality_map.json，调参改表不改代码。

const DIMS := ["sociable", "shrewd", "composed", "fastidious", "agreeable"]


static func map() -> Dictionary:
	return DataDB.load_table("personality_map")


## 按权重抽一个原型 id。
static func pick_archetype(rng: GameRng) -> String:
	var w := {}
	var a: Dictionary = map()["archetypes"]
	for id in a:
		w[id] = float(a[id]["weight"])
	return str(rng.weighted_pick(w))


## 原型中心 + 每维噪声。
static func roll_vector(archetype: String, rng: GameRng) -> Dictionary:
	var m := map()
	var vec: Array = m["archetypes"][archetype]["vec"]
	var noise := float(m["dim_noise"])
	var out := {}
	for i in DIMS.size():
		out[DIMS[i]] = clampf(float(vec[i]) + rng.randfn(0.0, noise), 0.0, 1.0)
	return out


## 按映射表算出全部派生参数。rng 为 null 时不加噪声（老存档迁移、补缺字段用，结果确定）。
static func derive(vec: Dictionary, rng: GameRng = null) -> Dictionary:
	var m := map()
	var out := {}
	for spec in m["derived"]:
		var v := float(spec.get("const", 0.0))
		for term in spec.get("terms", []):
			var t := float(term[0])
			for j in range(1, term.size()):
				t *= _value(str(term[j]), vec, out)
			v += t
		if rng != null:
			v += rng.randfn(0.0, float(spec.get("noise", 0.0)))
		if spec.get("round", false):
			v = roundf(v)
		var c: Array = spec.get("clamp", [-INF, INF])
		out[spec["name"]] = clampf(v, float(c[0]), float(c[1]))
	out["haggle_strategy"] = strategy_of(vec)
	return out


static func _value(name: String, vec: Dictionary, derived: Dictionary) -> float:
	var inv := name.begins_with("~")
	var key := name.substr(1) if inv else name
	var v := float(vec.get(key, derived.get(key, 0.5)))
	return 1.0 - v if inv else v


static func strategy_of(vec: Dictionary) -> String:
	var t: Dictionary = map()["haggle_strategy"]
	if float(vec.get("shrewd", 0.5)) > float(t["direct_discount_shrewd"]):
		return "direct_discount"
	if float(vec.get("sociable", 0.5)) > float(t["fake_leave_sociable"]):
		return "fake_leave"
	return "tug_of_war"


## 最接近这个向量的原型（只比较 known 里给出的维度）。
static func nearest_archetype(vec: Dictionary, known: Array = DIMS) -> String:
	var a: Dictionary = map()["archetypes"]
	var best := ""
	var best_d := INF
	for id in a:
		var d := 0.0
		for i in DIMS.size():
			if known.has(DIMS[i]):
				d += pow(float(a[id]["vec"][i]) - float(vec.get(DIMS[i], 0.5)), 2)
		if d < best_d:
			best_d = d
			best = id
	return best


static func archetype_name(id: String) -> String:
	return str(map()["archetypes"].get(id, {}).get("name", ""))


## 客人观察 Lv4：最突出的两三个性格词（偏离中间越多越先说）。
static func describe(vec: Dictionary) -> Array:
	var m := map()
	var devs: Array = []
	for d in DIMS:
		var dev := float(vec.get(d, 0.5)) - 0.5
		if absf(dev) >= float(m["min_dev"]):
			devs.append([absf(dev), d, dev > 0.0])
	devs.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for i in mini(devs.size(), int(m["max_words"])):
		out.append(m["words"][devs[i][1]][0 if devs[i][2] else 1])
	return out
