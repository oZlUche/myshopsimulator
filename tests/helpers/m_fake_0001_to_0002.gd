extends RefCounted
## 测试用假迁移：把 player.cash 改名为 player.money。


func migrate(d: Dictionary) -> Dictionary:
	d["player"]["money"] = d["player"].get("cash", 0.0)
	d["player"].erase("cash")
	return d
