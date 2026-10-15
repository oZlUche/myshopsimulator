class_name Knowledge
extends RefCounted
## 认知层（01 §2.2）：玩家"以为"的世界。表现层只读这里，从不直接读真相层。

## 玩家手写标签 {slot_id: text}
var labels: Dictionary = {}
## 强化记忆：最近操作过的槽位快照，最新在前 [{slot_id, snapshot: [sku_id...], period}]
var recent_slots: Array = []
## 翻看结果 {item_id: {sku_guess, confidence, may_be_wrong}}
var perceived: Dictionary = {}
## 审美积累给出的趋势预报 [{period, text, ...}]
var trend_hints: Array = []
## 认知层账本条目（01 §4.5）
var ledger: Array = []


## 每次 place / take 都把槽位推到队首并去重；容量 N 由强化记忆等级决定（02 §2.2）。
func touch_slot(slot: Slot, capacity: int, period: int) -> void:
	recent_slots = recent_slots.filter(func(r): return r["slot_id"] != slot.id)
	if capacity <= 0:
		recent_slots.clear()
		return
	recent_slots.push_front({
		"slot_id": slot.id,
		"snapshot": slot.stack.items.map(func(i): return i.sku_id),
		"period": period,
	})
	while recent_slots.size() > capacity:
		recent_slots.pop_back()


func memory_of(slot_id: String) -> Variant:
	for r in recent_slots:
		if r["slot_id"] == slot_id:
			return r
	return null


func add_ledger(period: int, kind: String, amount: float, note: String) -> void:
	ledger.append({"period": period, "kind": kind, "amount": amount, "note": note})


func to_dict() -> Dictionary:
	return {
		"labels": labels.duplicate(), "recent_slots": recent_slots.duplicate(true),
		"perceived": perceived.duplicate(true), "trend_hints": trend_hints.duplicate(true),
		"ledger": ledger.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Knowledge:
	var k := Knowledge.new()
	k.labels = d.get("labels", {})
	k.recent_slots = d.get("recent_slots", [])
	k.perceived = d.get("perceived", {})
	k.trend_hints = d.get("trend_hints", [])
	k.ledger = d.get("ledger", [])
	return k
