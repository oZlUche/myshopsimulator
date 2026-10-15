extends RefCounted


func migrate(d: Dictionary) -> Dictionary:
	d["player"]["stamina"] = d["player"].get("stamina", 100.0)
	return d
