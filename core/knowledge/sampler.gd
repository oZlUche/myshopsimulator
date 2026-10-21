class_name Sampler
extends RefCounted
## 技能 = 采样参数（01 §2.2、02 §1）。所有"真相 → 认知"的有损转换都在这里。
## 每条提示带 precision：0 定性 / 1 区间 / 2 精确，上限由数学能手决定。


## 客人观察（02 §2.3 → 06 §4）：Lv1 第一条想要的；Lv2 剩余耐心次数；Lv3 预算；Lv4 两三个性格词；Lv5 回头倾向。
## patience_left 为正在讲价时剩几次（−1 表示还没讲价，按他的耐心总数说）。
static func customer_hint(c: CustomerProfile, player: PlayerState, sku_for_budget: String = "", patience_left: int = -1) -> Dictionary:
	var lv := player.skill_level("customer_observation")
	var prec := SkillSystem.precision_cap(player)
	var a := DataDB.attributes()
	var h := {"precision": prec}
	if lv >= 1 and not c.expectations.is_empty():
		var pref := c.preference
		h["preference"] = "想要%s、%s、%s" % [
			a["colors"][pref["color"]]["name"],
			a["patterns"][pref["pattern"]]["name"],
			a["materials"][pref["material"]]["name"],
		]
	if lv >= 2:
		h["patience"] = ("还能磨 %d 次" % patience_left) if patience_left >= 0 else ("大概能磨 %d 次" % c.patience_n)
	if lv >= 3 and sku_for_budget != "":
		var r := c.reserve_price(sku_for_budget)
		h["budget"] = ["预算不太宽裕" if r < float(DataDB.sku(sku_for_budget)["base_price"]) else "预算挺足",
			"约 %d–%d 元" % [roundi(r * 0.85), roundi(r * 1.15)], "%d 元" % roundi(r)][prec]
	if lv >= 4:
		var words := Personality.describe(c.personality)
		h["strategy"] = "、".join(words) if not words.is_empty() else "看不出什么特别"
	if lv >= 5:
		h["loyalty"] = _qual(c.loyalty_base, ["不太会再来", "可能再来", "很可能成为常客"], prec)
	return h


static func _qual(v: float, words: Array, prec: int) -> String:
	match prec:
		0:
			return words[clampi(int(v * words.size()), 0, words.size() - 1)]
		1:
			var lo := floorf(v * 5.0) / 5.0
			return "%d%%–%d%%" % [roundi(lo * 100), roundi(minf(lo + 0.2, 1.0) * 100)]
		_:
			return "%d%%" % roundi(v * 100)


## 强化记忆悬浮框（02 §2.2）：返回空字符串表示没有记忆。显示的是操作当时的快照。
static func memory_tooltip(k: Knowledge, slot_id: String, player: PlayerState) -> String:
	var lv := player.skill_level("memory")
	var r: Variant = k.memory_of(slot_id)
	if lv <= 0 or r == null:
		return ""
	var a := DataDB.attributes()
	var counts := {}
	var order: Array = []
	for sku_id in r["snapshot"]:
		var s := DataDB.sku(sku_id)
		var key: String
		if lv >= 2:
			key = "%s%s%s" % [a["colors"][s["color"]]["name"], a["patterns"][s["pattern"]]["name"], a["materials"][s["material"]]["name"]]
		else:
			key = "%s%s" % [a["patterns"][s["pattern"]]["name"], a["materials"][s["material"]]["name"]]
		if not counts.has(key):
			order.append(key)
		counts[key] = int(counts.get(key, 0)) + 1
	if order.is_empty():
		return "（空）"
	if lv >= 4:
		return "、".join(order.map(func(k): return "%s×%d" % [k, counts[k]]))
	return "、".join(order)


## 翻看（03 §3）：按图案相似度表（与 06 §2 客人看货共用）可能认成同色同材质的别的图案款。
## 纯色几乎不认错，格纹 / 条纹、碎花 / 波点之间最容易看混。
static func peek(item: ScarfItem, rng: GameRng) -> Dictionary:
	var s := DataDB.sku(item.sku_id)
	var a := DataDB.attributes()
	var confusable: bool = a["patterns"][s["pattern"]].get("confusable", false)
	var conf := AttrDistance.pattern_confusion(s["pattern"])
	var p_confuse := 0.0
	for q in conf:
		p_confuse += float(conf[q])
	var guess := item.sku_id
	var roll := rng.randf()
	for q in conf:
		roll -= float(conf[q])
		if roll < 0.0:
			guess = "scarf_%s_%s_%s" % [q, s["color"], s["material"]]
			break
	return {"sku_guess": guess, "confidence": 1.0 - p_confuse, "may_be_wrong": confusable}


## 审美积累（02 §2.1）：旬末对未来趋势的预报。
static func trend_forecast(trend: TrendState, period: int, player: PlayerState, rng: GameRng) -> Array:
	var lv := player.skill_level("aesthetics")
	if lv <= 0:
		return []
	if lv < 6 and not rng.chance(0.35):
		return []
	var upcoming := trend.upcoming_jumps(period)
	upcoming.shuffle()
	var count := 999 if lv >= 7 else mini(lv, 3)
	var prec := SkillSystem.precision_cap(player)
	var a := DataDB.attributes()
	var out: Array = []
	for j in upcoming.slice(0, count):
		var key_name: String = a["colors"][j["key"]]["name"] if j["dim"] == "color" else a["patterns"][j["key"]]["name"]
		var text := "%s会比较流行" % key_name
		if prec >= 1:
			var b := float(j["boost"])
			text = "%s需求将提升 %d%%~%d%%" % [key_name, roundi(b * 80), roundi(b * 120)] if prec == 1 \
				else "%s需求将提升约 %d%%" % [key_name, roundi(b * 100)]
		if lv >= 5:
			text += "，持续约 %d 旬" % int(j["duration"])
		elif lv >= 4:
			var dur := int(j["duration"])
			text += "，" + ("持续一阵子" if dur <= 4 else ("大约一个季度" if dur <= 9 else "会持续很长时间"))
		out.append({"period": period, "text": text, "precision": prec})
	return out
