class_name ScarfItem
extends RefCounted
## 真相层：一条具体的围巾。quality 在品质开关关闭时为 null（05 文档）。

var id: String
var sku_id: String
var quality: Variant = null
## 来源：厂商、批次、进货旬、搬运次数等。
var provenance: Dictionary = {}


func _init(item_id: String = "", sku: String = "") -> void:
	id = item_id
	sku_id = sku


func to_dict() -> Dictionary:
	return {"id": id, "sku_id": sku_id, "quality": quality, "provenance": provenance.duplicate(true)}


static func from_dict(d: Dictionary) -> ScarfItem:
	var it := ScarfItem.new(str(d.get("id", "")), str(d.get("sku_id", "")))
	it.quality = d.get("quality", null)
	it.provenance = d.get("provenance", {})
	return it
