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
