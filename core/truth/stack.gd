class_name ItemStack
extends RefCounted
## 有序货堆（03 文档 §1）。items[0] 为底部，末尾为顶部。
## 命名为 ItemStack 以避开 Godot 内置名。

var items: Array[ScarfItem] = []
var max_height: int = 4
var disorder: float = 0.0
var displaced: bool = false
var collapsed_pile: Array[ScarfItem] = []


func height() -> int:
	return items.size()


func is_full() -> bool:
	return items.size() >= max_height


func top() -> ScarfItem:
	return null if items.is_empty() else items[-1]


## 第 index 份上方的份数 N。
func count_above(index: int) -> int:
	return items.size() - 1 - index


## 第 index 份上方的总重量 W（按材质加权）。
func weight_above(index: int) -> float:
	var w := 0.0
	var mats: Dictionary = DataDB.attributes()["materials"]
	for i in range(index + 1, items.size()):
		var sku := DataDB.sku(items[i].sku_id)
		w += float(mats.get(sku.get("material", ""), {}).get("weight", 1.0))
	return w


## 第 index 份实际所在的层（算上下面空出来的层）。
func layer_of(index: int) -> int:
	var layer := 0
	for i in index + 1:
		layer += items[i].gap_below
	return layer + index


## 压实：上面的货落下去把空隙填上（放顶、拾起放回时，03 §2.4）。
func settle() -> void:
	for it in items:
		it.gap_below = 0


func index_of(item_id: String) -> int:
	for i in items.size():
		if items[i].id == item_id:
			return i
	return -1


## 重新计算混乱度：相邻两份 SKU 不同的比例。
func recompute_disorder() -> void:
	if items.size() < 2:
		disorder = 0.0
		return
	var breaks := 0
	for i in range(1, items.size()):
		if items[i].sku_id != items[i - 1].sku_id:
			breaks += 1
	# 不同 SKU 数量决定最少断点；超出部分才算"乱"。
	var kinds := {}
	for it in items:
		kinds[it.sku_id] = true
	var min_breaks := kinds.size() - 1
	var max_extra := items.size() - 1 - min_breaks
	disorder = 0.0 if max_extra <= 0 else clampf(float(breaks - min_breaks) / max_extra, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"items": items.map(func(i): return i.to_dict()),
		"max_height": max_height,
		"disorder": disorder,
		"displaced": displaced,
		"collapsed_pile": collapsed_pile.map(func(i): return i.to_dict()),
	}


static func from_dict(d: Dictionary) -> ItemStack:
	var s := ItemStack.new()
	for x in d.get("items", []):
		s.items.append(ScarfItem.from_dict(x))
	for x in d.get("collapsed_pile", []):
		s.collapsed_pile.append(ScarfItem.from_dict(x))
	s.max_height = int(d.get("max_height", 4))
	s.disorder = float(d.get("disorder", 0.0))
	s.displaced = bool(d.get("displaced", false))
	return s
