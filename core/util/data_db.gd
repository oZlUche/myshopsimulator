class_name DataDB
extends RefCounted
## 只读数据表的加载与缓存（res://data/*.json）。数据表全部用稳定字符串 ID。

static var _cache: Dictionary = {}
static var _skus: Dictionary = {}


static func load_table(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var path := "res://data/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataDB: 无法打开 %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	var table: Dictionary = parsed if parsed is Dictionary else {}
	table.erase("_comment")
	_cache[name] = table
	return table


static func attributes() -> Dictionary:
	return load_table("scarf_attributes")


static func skills() -> Dictionary:
	return load_table("skills")


static func equipment() -> Dictionary:
	return load_table("equipment")


## 全部 SKU：{sku_id: {id, pattern, color, material, base_cost, base_price}}
static func skus() -> Dictionary:
	if not _skus.is_empty():
		return _skus
	var a := attributes()
	var markup: float = a.get("retail_markup", 2.0)
	for p in a["patterns"]:
		for c in a["colors"]:
			for m in a["materials"]:
				var id := "scarf_%s_%s_%s" % [p, c, m]
				var cost := float(a["materials"][m]["base_cost"]) * float(a["patterns"][p]["price_mult"])
				_skus[id] = {
					"id": id, "pattern": p, "color": c, "material": m,
					"base_cost": snappedf(cost, 0.5),
					"base_price": snappedf(cost * markup, 1.0),
				}
	return _skus


static func sku(sku_id: String) -> Dictionary:
	return skus().get(sku_id, {})


static func sku_display_name(sku_id: String) -> String:
	var s := sku(sku_id)
	if s.is_empty():
		return sku_id
	var a := attributes()
	return "%s%s%s围巾" % [a["colors"][s["color"]]["name"], a["patterns"][s["pattern"]]["name"], a["materials"][s["material"]]["name"]]
