class_name EconomyState
extends RefCounted
## 真相层：双循环宏观经济（01 §4.2）。E(t) = Base(year) + C(t) + Season(t)。
## Base 只读年度 Δ 历史；C 只读最近 ≤36 旬观测；两者互不读取，最后相加。

const OBS_WINDOW := 36

## 年度基准（每 36 旬随机调整一次）。material_bias 为对季节基线的偏移。
var base: Dictionary = {
	"consumption_level": 1.0,
	"material_bias": {},
	"wholesale_credit_risk": 0.1,
	"loan_rate_base": 0.05,
}
## 每年一条：{"consumption_level": Δ}
var base_delta_history: Array = []
## 最近旬的观测向量（最新在末尾）：{"price_ratio": 成交价/标价 - 1, "sales": 成交件数, "traffic": 过路客数}
var observations: Array = []
var lambda_: float = 0.88
## C(t) 对消费水平的影响系数。
var continuous_gain: float = 0.5


## 连续循环 C(t)：最近 ≤36 旬观测的指数衰减加权平均（只用 price_ratio 一维，后续可扩展）。
func continuous_term() -> float:
	if observations.is_empty():
		return 0.0
	var num := 0.0
	var den := 0.0
	var n: int = min(observations.size(), OBS_WINDOW)
	for i in range(1, n + 1):
		var w := pow(lambda_, i)
		var obs: Dictionary = observations[observations.size() - i]
		num += w * float(obs.get("price_ratio", 0.0))
		den += w
	return continuous_gain * num / den


## 季节材质基线，换季前后各 1 旬线性插值。
static func season_material(period: int) -> Dictionary:
	var baselines: Dictionary = DataDB.attributes()["season_material_baseline"]
	var s := Clock.season_of(period)
	var k := (period - 1) % Clock.PERIODS_PER_SEASON
	var cur: Dictionary = baselines[Clock.SEASON_IDS[s]]
	var other: Dictionary = {}
	var t := 0.0
	if k == Clock.PERIODS_PER_SEASON - 1:
		other = baselines[Clock.SEASON_IDS[(s + 1) % 4]]
		t = 0.25
	elif k == 0:
		other = baselines[Clock.SEASON_IDS[(s + 3) % 4]]
		t = 0.25
	if other.is_empty():
		return cur.duplicate()
	var out := {}
	for m in cur:
		out[m] = lerpf(float(cur[m]), float(other.get(m, 0.0)), t)
	return out


## 本旬有效经济状态。
func effective(period: int) -> Dictionary:
	var mat := season_material(period)
	var bias: Dictionary = base.get("material_bias", {})
	var total := 0.0
	for m in mat:
		mat[m] = maxf(0.001, float(mat[m]) + float(bias.get(m, 0.0)))
		total += mat[m]
	for m in mat:
		mat[m] = mat[m] / total
	return {
		"consumption_level": maxf(0.3, float(base["consumption_level"]) + continuous_term()),
		"material_pref": mat,
		"wholesale_credit_risk": base["wholesale_credit_risk"],
		"loan_rate_base": base["loan_rate_base"],
	}


func push_observation(obs: Dictionary) -> void:
	observations.append(obs)
	while observations.size() > OBS_WINDOW:
		observations.pop_front()


## 年末：Δ_k ~ f(Δ_1..Δ_{k-1}) + noise。带轻微均值回归：连续上行后下行概率增大。
func year_end_step(rng: GameRng) -> Dictionary:
	var prev := 0.0
	var prev2 := 0.0
	if base_delta_history.size() >= 1:
		prev = float(base_delta_history[-1].get("consumption_level", 0.0))
	if base_delta_history.size() >= 2:
		prev2 = float(base_delta_history[-2].get("consumption_level", 0.0))
	var mean := 0.25 * prev - 0.35 * (prev + prev2) * 0.5
	var delta_c := clampf(mean + rng.randfn(0.0, 0.07), -0.25, 0.25)
	base["consumption_level"] = clampf(float(base["consumption_level"]) + delta_c, 0.5, 1.8)
	var bias: Dictionary = base.get("material_bias", {})
	var delta_m := {}
	for m in DataDB.attributes()["materials"]:
		var dm := rng.randfn(0.0, 0.015)
		delta_m[m] = dm
		bias[m] = clampf(float(bias.get(m, 0.0)) * 0.6 + dm, -0.08, 0.08)
	base["material_bias"] = bias
	var d := {"consumption_level": delta_c, "material_bias": delta_m}
	base_delta_history.append(d)
	return d


func to_dict() -> Dictionary:
	return {
		"base": base.duplicate(true),
		"base_delta_history": base_delta_history.duplicate(true),
		"observations": observations.duplicate(true),
		"lambda": lambda_,
		"continuous_gain": continuous_gain,
	}


static func from_dict(d: Dictionary) -> EconomyState:
	var e := EconomyState.new()
	var b: Dictionary = d.get("base", {})
	for k in b:
		e.base[k] = b[k]
	e.base_delta_history = d.get("base_delta_history", [])
	e.observations = d.get("observations", [])
	e.lambda_ = float(d.get("lambda", 0.88))
	e.continuous_gain = float(d.get("continuous_gain", 0.5))
	return e
