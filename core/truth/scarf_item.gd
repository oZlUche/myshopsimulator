class_name ScarfItem
extends RefCounted
## 真相层：一条具体的围巾。quality 在品质开关关闭时为 null（05 文档）。

var id: String
var sku_id: String
var quality: Variant = null
## 来源：厂商、批次、进货旬、搬运次数等。
var provenance: Dictionary = {}
## 抽取进度（03 §2）：货抽出去多少就停在多少，不会缩回。占货长的比例，带方向（±），|out| ≥ 0.5 即抽出。
var pull_out := 0.0
## 已抽部分的偏差分，按抽出距离加权累计：平均偏差 = d_sum / w_sum。
var pull_d_sum := 0.0
var pull_w_sum := 0.0
## 被下方抽货带歪的横向位移（占货长的比例，±）。摆放状态保留，理货时才归位。
var shift := 0.0


func _init(item_id: String = "", sku: String = "") -> void:
	id = item_id
	sku_id = sku


func reset_pull() -> void:
	pull_out = 0.0
	pull_d_sum = 0.0
	pull_w_sum = 0.0
	shift = 0.0


func to_dict() -> Dictionary:
	var d := {"id": id, "sku_id": sku_id, "quality": quality, "provenance": provenance.duplicate(true)}
	# 只有动过的货才写，老存档读进来就是 0
	if pull_out != 0.0 or shift != 0.0 or pull_w_sum != 0.0:
		d["pull"] = {"out": pull_out, "d_sum": pull_d_sum, "w_sum": pull_w_sum, "shift": shift}
	return d


static func from_dict(d: Dictionary) -> ScarfItem:
	var it := ScarfItem.new(str(d.get("id", "")), str(d.get("sku_id", "")))
	it.quality = d.get("quality", null)
	it.provenance = d.get("provenance", {})
	var pull: Dictionary = d.get("pull", {})
	it.pull_out = float(pull.get("out", 0.0))
	it.pull_d_sum = float(pull.get("d_sum", 0.0))
	it.pull_w_sum = float(pull.get("w_sum", 0.0))
	it.shift = float(pull.get("shift", 0.0))
	return it
