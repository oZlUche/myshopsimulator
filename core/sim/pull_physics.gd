class_name PullPhysics
extends RefCounted
## 抽取结算（03 §2.2）。玩家小游戏输入与客人 / 员工属性都先归一化成偏差分 d，再走同一个结算函数。

const OPTIMAL_ANGLE_DEG := 37.5
const POINT_FACTOR := {"corner": 1.0, "edge": 0.7, "center": 0.4}

# 系数（待实测调整）
static var k_w := 0.35
static var a_angle := 1.0
static var b_point := 1.2
static var c_early := 1.5
static var e_jerk := 0.8
static var v_slow := 0.3
static var alpha := 2.2
static var beta := 0.45
static var gamma := 4.0
static var shift_scale := 0.25
static var shift_threshold := 0.5


static func f_angle(theta_deg: float) -> float:
	return 1.0 if theta_deg >= 30.0 and theta_deg <= 45.0 else lerpf(0.5, 1.0, 1.0 - minf(absf(theta_deg - OPTIMAL_ANGLE_DEG) / 52.5, 1.0))


## 货物实际跟手速度（小游戏表现层用）。
static func item_speed(v_hand: float, weight_above: float, theta_deg: float, point: String) -> float:
	return v_hand / (1.0 + k_w * weight_above) * f_angle(theta_deg) * float(POINT_FACTOR.get(point, 0.4))


## 玩家输入 → 偏差分。input: {angle_deg, point, early_speed, jerk}
static func deviation_from_input(input: Dictionary) -> float:
	var theta := float(input.get("angle_deg", OPTIMAL_ANGLE_DEG))
	var angle_dev := 0.0 if theta >= 30.0 and theta <= 45.0 else absf(theta - OPTIMAL_ANGLE_DEG) / OPTIMAL_ANGLE_DEG
	var point_dev := 1.0 - float(POINT_FACTOR.get(input.get("point", "center"), 0.4))
	return a_angle * angle_dev \
		+ b_point * point_dev \
		+ c_early * maxf(0.0, float(input.get("early_speed", 0.0)) - v_slow) \
		+ e_jerk * float(input.get("jerk", 0.0))


## 客人 / 员工属性 → 偏差分（03 §5）。profile: {careless, patience, first_visit, skill}
static func deviation_from_actor(profile: Dictionary, rng: GameRng) -> float:
	var base := 0.6 + 1.2 * float(profile.get("careless", 0.3)) + 0.6 * (1.0 - float(profile.get("patience", 0.5)))
	if profile.get("first_visit", false):
		base += 0.3
	base -= 0.25 * float(profile.get("skill", 0.0))
	return maxf(0.0, base + rng.randfn(0.0, 0.25))


static func collapse_probability(d: float, n_above: int) -> float:
	if n_above <= 0:
		return 0.0
	return 1.0 / (1.0 + exp(-(alpha * d + beta * n_above - gamma)))


## 结算一次抽取。返回 {collapsed, displaced, d, p_collapse}。
static func resolve(d: float, n_above: int, rng: GameRng) -> Dictionary:
	var p := collapse_probability(d, n_above)
	var collapsed := rng.chance(p)
	var displaced := not collapsed and d * n_above * shift_scale > shift_threshold
	return {"collapsed": collapsed, "displaced": displaced, "d": d, "p_collapse": p}


## 小游戏拖动轨迹 → 玩家输入（03 §2.1）。samples: [{t: 秒, pos: Vector2(像素)}]，按时间顺序。
## point: 按下的位置是 corner / edge / center。speed_unit: 多少像素/秒算 1.0 的手速。
static func input_from_drag(samples: Array, point: String, speed_unit: float = 600.0) -> Dictionary:
	if samples.size() < 2:
		return {"angle_deg": 0.0, "point": point, "early_speed": 0.0, "jerk": 0.0}
	var first: Vector2 = samples[0]["pos"]
	var last: Vector2 = samples[-1]["pos"]
	var d := last - first
	# 屏幕坐标 y 向下；角度只看与水平面的夹角
	var angle := rad_to_deg(atan2(absf(d.y), absf(d.x))) if d.length() > 0.01 else 0.0
	var duration := maxf(0.001, float(samples[-1]["t"]) - float(samples[0]["t"]))
	var speeds: Array[float] = []
	for i in range(1, samples.size()):
		var dt := maxf(0.001, float(samples[i]["t"]) - float(samples[i - 1]["t"]))
		speeds.append((samples[i]["pos"] - samples[i - 1]["pos"]).length() / dt / speed_unit)
	# 起手：前 30% 时间的平均手速
	var early_sum := 0.0
	var early_n := 0
	var t0 := float(samples[0]["t"])
	for i in speeds.size():
		if float(samples[i + 1]["t"]) - t0 <= duration * 0.3:
			early_sum += speeds[i]
			early_n += 1
	if early_n == 0:
		early_sum = speeds[0]
		early_n = 1
	# 突变：相邻手速差的最大值（先慢后快是平滑加速，不算突变）
	var jerk := 0.0
	for i in range(1, speeds.size()):
		jerk = maxf(jerk, absf(speeds[i] - speeds[i - 1]) - 0.15)
	return {"angle_deg": angle, "point": point, "early_speed": early_sum / early_n, "jerk": maxf(0.0, jerk)}
