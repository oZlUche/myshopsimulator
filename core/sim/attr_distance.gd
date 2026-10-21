class_name AttrDistance
extends RefCounted
## 货与客人预期之间的属性距离（06 §2）。三个维度各给 0..1 的距离，按预期值的权重加权成 d。
## 数据在 data/scarf_attributes.json：颜色的 hue / light / chroma，图案与材质的两两相似度表。
## 图案相似度同时决定翻看时认成哪一款（03 §3），两边共用一张表。

## 认错概率 = CONFUSE_SCALE × 相似度²，对所有别的图案求和（纯色约 2%，图案款 10%–16%）
const CONFUSE_SCALE := 0.32
const DEFAULT_WEIGHT := {"color": 0.4, "material": 0.3, "pattern": 0.3}


## 颜色距离：色相差（按两者里较低的彩度打折，黑白灰没有色相）+ 明度差 + 彩度差。
static func color(a: String, b: String) -> float:
	if a == b:
		return 0.0
	var cs: Dictionary = DataDB.attributes()["colors"]
	var ca: Dictionary = cs[a]
	var cb: Dictionary = cs[b]
	var dh := absf(float(ca["hue"]) - float(cb["hue"]))
	dh = minf(dh, 360.0 - dh) / 180.0
	var d := 0.6 * dh * minf(float(ca["chroma"]), float(cb["chroma"])) \
		+ 0.7 * absf(float(ca["light"]) - float(cb["light"])) \
		+ 0.4 * absf(float(ca["chroma"]) - float(cb["chroma"]))
	return clampf(d, 0.0, 1.0)


static func _sim(table: String, a: String, b: String) -> float:
	if a == b:
		return 1.0
	var t: Dictionary = DataDB.attributes().get(table, {})
	return float(t.get("%s|%s" % [a, b], t.get("%s|%s" % [b, a], 0.0)))


static func pattern_similarity(a: String, b: String) -> float:
	return _sim("pattern_similarity", a, b)


static func material_similarity(a: String, b: String) -> float:
	return _sim("material_similarity", a, b)


static func pattern(a: String, b: String) -> float:
	return 1.0 - pattern_similarity(a, b)


static func material(a: String, b: String) -> float:
	return 1.0 - material_similarity(a, b)


## 一份货（SKU）与一条预期值 {color, material, pattern, weight?} 的差值 d：
## d = w_c·d_color + w_m·d_material + w_p·d_pattern。
static func to_expectation(sku_id: String, e: Dictionary) -> float:
	var s := DataDB.sku(sku_id)
	if s.is_empty():
		return 1.0
	var w: Dictionary = e.get("weight", DEFAULT_WEIGHT)
	return float(w.get("color", 0.0)) * color(s["color"], e["color"]) \
		+ float(w.get("material", 0.0)) * material(s["material"], e["material"]) \
		+ float(w.get("pattern", 0.0)) * pattern(s["pattern"], e["pattern"])


## 初始成交可能性 P0 = clamp(1 − (d / tol)^1.5, 0.25, 0.90)（只对 d ≤ tol 的货有意义）。
static func initial_p(d: float, tol: float) -> float:
	return clampf(1.0 - pow(d / maxf(tol, 0.001), 1.5), 0.25, 0.9)


## 翻看时把这款图案认成别的图案的概率：{别的图案: 概率}。
static func pattern_confusion(p: String) -> Dictionary:
	var out := {}
	for q in DataDB.attributes()["patterns"]:
		if q == p:
			continue
		var sim := pattern_similarity(p, q)
		if sim > 0.0:
			out[q] = CONFUSE_SCALE * sim * sim
	return out
