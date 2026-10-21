class_name Wholesale
extends RefCounted
## 批发进货的货怎么装（07 §1）：一包同一款若干条，单色包或混色包；若干包装一箱，箱外贴物流单。

const PACK_SIZE := 10
const BOX_PACKS := 10
## 批发价相对厂价 base_cost 的倍率：单色包贵一点，混色包便宜（07 §1.1）
const PRICE_MULT := {"single": 0.92, "mixed": 0.85}
## 混色包里有几种颜色
const MIX_COLORS := [3, 5]
const SENDERS := ["义乌·锦绣围巾厂", "杭州·丝路服饰", "广州·白马批发 3 楼", "海宁·暖绒针织厂", "绍兴·柯桥轻纺城"]


## 一条围巾的批发单价。
static func unit_cost(pattern: String, material: String, mix: String) -> float:
	var any := "scarf_%s_%s_%s" % [pattern, "black", material]
	return snappedf(float(DataDB.sku(any)["base_cost"]) * float(PRICE_MULT.get(mix, 1.0)), 0.5)


## 一包。single 用 color 那一种色；mixed 按 color_weights 挑 3–5 种色，条数随机分（每种至少 1 条），袋里顺序打乱。
static func make_pack(inv: Inventory, pattern: String, material: String, mix: String, color: String,
		color_weights: Dictionary, rng: GameRng, provenance: Dictionary) -> Package:
	var p := inv.create_package("pack")
	p.mix = mix
	p.sticker = {"pattern": pattern, "material": material}
	p.provenance = provenance.duplicate()
	var colors: Array = []
	if mix == "mixed":
		var pool := color_weights.duplicate()
		var n := rng.randi_range(int(MIX_COLORS[0]), int(MIX_COLORS[1]))
		while colors.size() < n and not pool.is_empty():
			var c: String = rng.weighted_pick(pool)
			pool.erase(c)
			colors.append(c)
		var counts := {}
		for c in colors:
			counts[c] = 1
		for i in PACK_SIZE - colors.size():
			var c: String = rng.pick(colors)
			counts[c] = int(counts[c]) + 1
		var order: Array = []
		for c in counts:
			for i in int(counts[c]):
				order.append(c)
		for i in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = order[i]
			order[i] = order[j]
			order[j] = t
		colors = order
	else:
		for i in PACK_SIZE:
			colors.append(color)
	for c in colors:
		p.items.append(inv.create_item("scarf_%s_%s_%s" % [pattern, c, material], provenance.duplicate()))
	return p


## 一批货：lines = [{pattern, material, mix, color?, packs}]，按顺序每 BOX_PACKS 包装一箱。
## 返回箱子列表，物流单写同一个发货方、"第 i 件 / 共 n 件"、毛重。
static func make_shipment(inv: Inventory, lines: Array, color_weights: Dictionary, rng: GameRng, period: int) -> Array[Package]:
	var packs: Array[Package] = []
	for line in lines:
		var mix: String = line.get("mix", "single")
		var cost := unit_cost(line["pattern"], line["material"], mix)
		var prov := {"bought_period": period, "unit_cost": cost, "source": "wholesale"}
		for i in int(line["packs"]):
			packs.append(make_pack(inv, line["pattern"], line["material"], mix, str(line.get("color", "")), color_weights, rng, prov))
	var boxes: Array[Package] = []
	var sender: String = rng.pick(SENDERS)
	var n_boxes := ceili(packs.size() / float(BOX_PACKS))
	for b in n_boxes:
		var box := inv.create_package("box")
		box.provenance = {"bought_period": period, "source": "wholesale"}
		for i in range(b * BOX_PACKS, mini(packs.size(), (b + 1) * BOX_PACKS)):
			box.packs.append(packs[i])
		box.waybill = {"sender": sender, "piece": b + 1, "of": n_boxes, "weight": box_weight(box)}
		boxes.append(box)
	return boxes


## 毛重（kg）：每条按材质轻重算，外加纸箱。
static func box_weight(box: Package) -> float:
	var mats: Dictionary = DataDB.attributes()["materials"]
	var w := 1.2
	for it in box.all_items():
		w += 0.15 * float(mats.get(DataDB.sku(it.sku_id).get("material", ""), {}).get("weight", 1.0))
	return snappedf(w, 0.1)
