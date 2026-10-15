class_name LocalSupplier
extends RefCounted
## 摆摊阶段的本地进货店（01 §6.1）。目录每旬刷新，偏向当季材质；只展示外观属性，不展示趋势。


## 生成本旬目录 [{sku_id, unit_price, stock}]
static func refresh_catalog(econ: Dictionary, rng: GameRng, size: int = 10) -> Array:
	var all := DataDB.skus()
	var weights := {}
	var mat_pref: Dictionary = econ["material_pref"]
	for id in all:
		weights[id] = float(mat_pref.get(all[id]["material"], 0.01)) + 0.02
	var picked := {}
	var guard := 0
	while picked.size() < size and guard < 500:
		guard += 1
		picked[rng.weighted_pick(weights)] = true
	var out: Array = []
	for id in picked:
		out.append({
			"sku_id": id,
			"unit_price": snappedf(float(all[id]["base_cost"]) * rng.randf_range(1.05, 1.3), 0.5),
			"stock": rng.randi_range(3, 12),
		})
	out.sort_custom(func(a, b): return a["sku_id"] < b["sku_id"])
	return out
