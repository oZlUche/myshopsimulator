class_name LocalSupplier
extends RefCounted
## 摆摊阶段的本地进货店（01 §6.1）。目录每旬刷新，偏向当季材质；只展示外观属性，不展示趋势。
## 进货单价 = base_cost · π · M_m · (1 + 0.25·g) · S_mat · U(1.05, 1.3)（09 §3.1，本地店的渠道系数就是那个 U）。


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
	var pi := float(econ.get("price_level", 1.0))
	var cost_mult: Dictionary = econ.get("material_cost_mult", {})
	var out: Array = []
	for id in picked:
		var cost_real := float(all[id]["base_cost"]) * float(cost_mult.get(all[id]["material"], 1.0))
		out.append({
			"sku_id": id,
			"unit_price": snappedf(cost_real * pi * rng.randf_range(1.05, 1.3), 0.5),
			"stock": rng.randi_range(3, 12),
		})
	out.sort_custom(func(a, b): return a["sku_id"] < b["sku_id"])
	return out
