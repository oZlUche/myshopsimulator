class_name Street
extends RefCounted
## 摆摊街区（01 §6.9）：一维街道上的人流场 + 已摆摊商贩的排他半径。
## 人流密度不直接展示给玩家，表现层只能画出走过的行人。

var length: float = 60.0
## 人流峰值 [{x, sigma, peak}]，叠加成密度曲线
var hotspots: Array = []
## 已在摆摊的商贩 [{id, x, radius}]
var vendors: Array = []
var base_density: float = 0.15


static func generate(rng: GameRng) -> Street:
	var s := Street.new()
	for i in rng.randi_range(2, 3):
		s.hotspots.append({"x": rng.randf_range(5.0, 55.0), "sigma": rng.randf_range(4.0, 10.0), "peak": rng.randf_range(0.6, 1.2)})
	# 商贩倾向扎堆在人多的地方
	for i in rng.randi_range(3, 5):
		var h: Dictionary = rng.pick(s.hotspots)
		s.vendors.append({"id": "vendor_%d" % i, "x": clampf(float(h["x"]) + rng.randfn(0.0, 6.0), 1.0, 59.0), "radius": rng.randf_range(2.0, 3.5)})
	return s


## 位置 x、旬内时段 t∈[0,1] 的人流密度（人/秒·格）。午间与傍晚两个高峰。
func density(x: float, t: float = 0.5) -> float:
	var d := base_density
	for h in hotspots:
		var dx := (x - float(h["x"])) / float(h["sigma"])
		d += float(h["peak"]) * exp(-0.5 * dx * dx)
	var time_mult := 0.6 + 0.4 * exp(-pow((t - 0.35) / 0.12, 2)) + 0.5 * exp(-pow((t - 0.75) / 0.1, 2))
	return d * time_mult


func can_place(x: float) -> bool:
	if x < 0.0 or x > length:
		return false
	for v in vendors:
		if absf(x - float(v["x"])) < float(v["radius"]):
			return false
	return true


## 摊位附近的商贩竞争：周遭范围内的商贩会分流逗留率。
func competition(x: float, area_radius: int) -> float:
	var c := 0.0
	for v in vendors:
		var dist := absf(x - float(v["x"]))
		if dist < area_radius + 4.0:
			c += 0.15 * (1.0 - dist / (area_radius + 4.0))
	return clampf(c, 0.0, 0.6)


func to_dict() -> Dictionary:
	return {"length": length, "hotspots": hotspots.duplicate(true), "vendors": vendors.duplicate(true), "base_density": base_density}


static func from_dict(d: Dictionary) -> Street:
	var s := Street.new()
	s.length = float(d.get("length", 60.0))
	s.hotspots = d.get("hotspots", [])
	s.vendors = d.get("vendors", [])
	s.base_density = float(d.get("base_density", 0.15))
	return s
