class_name TrendState
extends RefCounted
## 真相层：颜色与图案的时尚趋势（01 §4.2 d）。缓慢随机游走 + 预先排期的跳变。
## 跳变提前排期，这样【审美积累】才有"未来"可以预报（02 §2.1）。

var color: Dictionary = {}
var pattern: Dictionary = {}
## [{dim: "color"/"pattern", key, start_period, duration, boost}]
var scheduled_jumps: Array = []
var drift_sigma: float = 0.08
var jump_schedule_p: float = 0.3


static func create(rng: GameRng) -> TrendState:
	var t := TrendState.new()
	var a := DataDB.attributes()
	for c in a["colors"]:
		t.color[c] = rng.randf_range(0.7, 1.3)
	for p in a["patterns"]:
		t.pattern[p] = rng.randf_range(0.7, 1.3)
	t.pattern["solid"] = 1.5  # 纯色是常青款
	return t


func _boost(dim: String, key: String, period: int) -> float:
	var b := 0.0
	for j in scheduled_jumps:
		if j["dim"] == dim and j["key"] == key:
			var s := int(j["start_period"])
			if period >= s and period < s + int(j["duration"]):
				b += float(j["boost"])
	return b


## 本旬归一化后的偏好分布。
func effective(period: int) -> Dictionary:
	return {"color": _normalized("color", color, period), "pattern": _normalized("pattern", pattern, period)}


func _normalized(dim: String, src: Dictionary, period: int) -> Dictionary:
	var out := {}
	var total := 0.0
	for k in src:
		out[k] = float(src[k]) * (1.0 + _boost(dim, k, period))
		total += out[k]
	for k in out:
		out[k] = out[k] / total
	return out


## 旬末漂移；可能排期一个 3–6 旬后开始的跳变。
func step(period: int, rng: GameRng) -> void:
	for dict in [color, pattern]:
		for k in dict:
			dict[k] = clampf(float(dict[k]) * exp(rng.randfn(0.0, drift_sigma)), 0.2, 3.0)
	if rng.chance(jump_schedule_p):
		var dim: String = "color" if rng.chance(0.5) else "pattern"
		var src: Dictionary = color if dim == "color" else pattern
		scheduled_jumps.append({
			"dim": dim,
			"key": rng.pick(src.keys()),
			"start_period": period + rng.randi_range(3, 6),
			"duration": rng.randi_range(3, 12),
			"boost": rng.randf_range(0.6, 1.5),
		})
	scheduled_jumps = scheduled_jumps.filter(func(j): return int(j["start_period"]) + int(j["duration"]) > period)


## 未来尚未开始的跳变（供审美积累采样，玩家不可直接读）。
func upcoming_jumps(period: int) -> Array:
	return scheduled_jumps.filter(func(j): return int(j["start_period"]) > period)


func to_dict() -> Dictionary:
	return {"color": color.duplicate(), "pattern": pattern.duplicate(), "scheduled_jumps": scheduled_jumps.duplicate(true),
		"drift_sigma": drift_sigma, "jump_schedule_p": jump_schedule_p}


static func from_dict(d: Dictionary) -> TrendState:
	var t := TrendState.new()
	t.color = d.get("color", {})
	t.pattern = d.get("pattern", {})
	t.scheduled_jumps = d.get("scheduled_jumps", [])
	t.drift_sigma = float(d.get("drift_sigma", 0.08))
	t.jump_schedule_p = float(d.get("jump_schedule_p", 0.3))
	return t
