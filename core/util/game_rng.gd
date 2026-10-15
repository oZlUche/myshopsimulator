class_name GameRng
extends RefCounted
## 可存档的确定性随机数。seed / state 以字符串存档，避免 JSON 浮点精度丢失 64 位整数。

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


func randf() -> float:
	return _rng.randf()


func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


func randfn(mean: float = 0.0, deviation: float = 1.0) -> float:
	return _rng.randfn(mean, deviation)


func chance(p: float) -> bool:
	return _rng.randf() < p


## 按权重字典 {key: weight} 抽取一个 key。
func weighted_pick(weights: Dictionary) -> Variant:
	var total := 0.0
	for k in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return null
	var r := _rng.randf() * total
	var last: Variant = null
	for k in weights:
		var w := maxf(0.0, float(weights[k]))
		last = k
		if r < w:
			return k
		r -= w
	return last


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


func to_dict() -> Dictionary:
	return {"seed": str(_rng.seed), "state": str(_rng.state)}


static func from_dict(d: Dictionary) -> GameRng:
	var g := GameRng.new()
	g._rng.seed = str(d.get("seed", "0")).to_int()
	g._rng.state = str(d.get("state", "0")).to_int()
	return g
