class_name Street
extends RefCounted
## 摆摊街区（01 §6.9）：一维街道上的人流场 + 已摆摊商贩的排他半径。
## 人流密度不直接展示给玩家，表现层只能画出走过的行人。

var length: float = 60.0
## 人流峰值 [{x, sigma, peak}]，叠加成密度曲线
var hotspots: Array = []
## 已在摆摊的商贩 [{id, x, y?, radius}]；y 是摊子中心横穿街的位置，老存档没有就用 DEFAULT_VENDOR_Y
var vendors: Array = []
var base_density: float = 0.15

## 商贩摊子中心默认所在的那一排（格坐标 gy，靠店面那侧）
const DEFAULT_VENDOR_Y := 1.5


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
	return d * time_curve(t)


## 一旬里人流随时段的起伏：午间与傍晚两个高峰（店面也用这条曲线）。
static func time_curve(t: float) -> float:
	return 0.6 + 0.4 * exp(-pow((t - 0.35) / 0.12, 2)) + 0.5 * exp(-pow((t - 0.75) / 0.1, 2))


static func vendor_pos(v: Dictionary) -> Vector2:
	return Vector2(float(v["x"]), float(v.get("y", DEFAULT_VENDOR_Y)))


## 能不能在 (x, y) 摆摊：离每个商贩摊子中心的直线距离都不小于它的排他半径（圆形判定）。
## 只给 x 时按商贩那一排算。
func can_place(x: float, y: float = DEFAULT_VENDOR_Y) -> bool:
	if x < 0.0 or x > length:
		return false
	var p := Vector2(x, y)
	for v in vendors:
		if p.distance_to(vendor_pos(v)) < float(v["radius"]):
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
