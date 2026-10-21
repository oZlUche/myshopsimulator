class_name EconomyState
extends RefCounted
## 真相层：双循环宏观经济（01 §4.2）。E(t) = Base(year) + C(t) + Season(t)。
## Base 只读年度 Δ 历史；C 只读最近 ≤36 旬观测；两者互不读取，最后相加。
## 景气 G = Base + C 是主驱动，物价 π、运力 F、材质供给冲击 M_m 等宏观状态每旬由 period_step 更新（09 §1、§2）。

const OBS_WINDOW := 36
## 连续循环 C（09 §1.1 v0.2）：每维观测相对自己窗口均值的偏离，按 λ 衰减加权，× 增益后夹到 ±C_MAX；观测不足 C_MIN_OBS 旬时为 0
const LAMBDA := 0.88
const C_GAIN := 0.1
const C_MAX := 0.15
const C_MIN_OBS := 4
## 各维权重与"显著单位"：成交价比动 0.10；成交量、客流相对自己均值动 30%
const DEV_WEIGHT := {"price_ratio": 0.5, "sales": 0.3, "traffic": 0.2}
const DEV_SCALE_PRICE := 0.10
const DEV_SCALE_REL := 0.3
## 景气 G 的范围（09 §1.1）
const G_MIN := 0.6
const G_MAX := 1.6
## 每旬通胀率 infl = i0 + e_i·g(t−1) + N(0, σ_i)，夹到 [INFL_MIN, INFL_MAX]（09 §1.2）
const INFL_BASE := 0.0008
const INFL_G := 0.004
const INFL_SD := 0.0005
const INFL_MIN := -0.001
const INFL_MAX := 0.004
## 利率对景气的弹性 e_r（09 §1.3）
const RATE_G := 0.08
## 运力：随机游走回归系数、噪声、对景气的弹性 e_F、季节系数（09 §1.4）
const FUEL_AR := 0.85
const FUEL_SD := 0.03
const FUEL_G := 0.3
const SEASON_FUEL := {"spring": 1.0, "summer": 0.97, "autumn": 1.0, "winter": 1.08}
## 材质供给冲击 M_m：回归系数、噪声、范围；偶发事件概率、幅度、衰减旬数（09 §1.6）
const SHOCK_AR := 0.9
const SHOCK_SD := 0.025
const SHOCK_MIN := 0.7
const SHOCK_MAX := 1.5
const SHOCK_EVENT_P := 0.02
const SHOCK_EVENT_SIZE := 0.15
const SHOCK_EVENT_LEN := 6
## 进货价对景气的弹性 e_s；季节压力 S_mat = 1 + k·(占比 / 平均占比 − 1)（09 §3.1 v0.2）
const SUPPLY_G := 0.25
const SEASON_PRESSURE_K := 0.1
const SEASON_PRESSURE_MIN := 0.9
const SEASON_PRESSURE_MAX := 1.08
## 消费能力 S = G^1.2（09 §3.3）
const SPEND_ELASTICITY := 1.2
## 租金目标 ρ = π·(1 + e_ρ·最近 12 旬 g 的均值)（09 §1.5）
const RENT_G := 0.25
const RENT_WINDOW := 12
## 拖账倾向 κ = κ0·(1 + 1.5·max(0, −g))（09 §1.7）
const CREDIT_RISK_G := 1.5

## 年度基准（每 36 旬随机调整一次）。material_bias 为对季节基线的偏移。
var base: Dictionary = {
	"consumption_level": 1.0,
	"material_bias": {},
	"wholesale_credit_risk": 0.1,
	"loan_rate_base": 0.05,
}
## 每年一条：{"consumption_level": Δ}
var base_delta_history: Array = []
## 最近旬的观测向量（最新在末尾）：{"price_ratio": 成交价/(标价·π) - 1, "sales": 成交件数, "traffic": 过路客数}
var observations: Array = []

## ---- 09 宏观状态（老存档没有就按 1 起步）----
## 物价水平 π，第 1 旬为 1。所有表里的价格都是实际值，名义价 = 实际值 × π。
var price_level: float = 1.0
## 上一旬的通胀率（算年化通胀给利率用）
var last_inflation: float = INFL_BASE
## 运力随机游走部分 F_rw
var fuel_index_rw: float = 1.0
## 材质供给冲击 M_m（不含偶发事件）{material: float}
var material_shock: Dictionary = {}
## 偶发材质事件 [{material, boost, start, duration}]，boost 在 duration 旬内线性衰减到 0
var material_events: Array = []
## 最近 RENT_WINDOW 旬的 g（租金目标用）
var g_history: Array = []
## 租金目标指数 ρ_target（每旬算，续约时读）
var rent_index_target: float = 1.0
## 税制参数（预留，只存不算，09 §3.6）。所得税超额累进：应税所得 0–30000 按 5%，30000–100000 按 10%，以上 20%（实际值）。
var policy: Dictionary = {
	"tax_sales_rate": 0.03,
	"tax_threshold": 30000.0,
	"income_exempt": 60000.0,
	"income_brackets": [0.05, 0.10, 0.20],
	"income_bracket_limits": [30000.0, 100000.0],
}


## 连续循环 C(t)（09 §1.1 v0.2）：只看"最近比自己过去好还是差"。每维观测减去窗口内（≤36 旬）等权均值，
## 除以显著单位，三维加权成 dev，再按 λ^i 衰减加权平均，× C_GAIN，夹到 ±C_MAX。玩家一贯卖得便宜或贵不会改变 G。
func continuous_term() -> float:
	var n: int = mini(observations.size(), OBS_WINDOW)
	if n < C_MIN_OBS:
		return 0.0
	var recent := observations.slice(observations.size() - n)
	var mean := {}
	for k in DEV_WEIGHT:
		var sum := 0.0
		for obs in recent:
			sum += float(obs.get(k, 0.0))
		mean[k] = sum / n
	var num := 0.0
	var den := 0.0
	for i in range(1, n + 1):
		var w := pow(LAMBDA, i)
		num += w * _deviation(recent[n - i], mean)
		den += w
	return clampf(C_GAIN * num / den, -C_MAX, C_MAX)


func _deviation(obs: Dictionary, mean: Dictionary) -> float:
	var dev := 0.0
	for k in DEV_WEIGHT:
		var m := float(mean[k])
		var scale := DEV_SCALE_PRICE if k == "price_ratio" else DEV_SCALE_REL * maxf(m, 1.0)
		dev += float(DEV_WEIGHT[k]) * (float(obs.get(k, m)) - m) / scale
	return dev


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


## 景气指数 G = Base + C（09 §1.1）。
func level() -> float:
	return clampf(float(base["consumption_level"]) + continuous_term(), G_MIN, G_MAX)


## 本旬有效经济状态。consumption_level 与 G 是同一个数（老代码读前者）。
## material_cost_mult[m] = M_m · (1 + e_s·g) · S_mat：进货价里除了 base_cost、π 和渠道 / 批量 / 议价以外的部分（09 §3.1）。
func effective(period: int) -> Dictionary:
	var mat := season_material(period)
	var bias: Dictionary = base.get("material_bias", {})
	var total := 0.0
	for m in mat:
		mat[m] = maxf(0.001, float(mat[m]) + float(bias.get(m, 0.0)))
		total += mat[m]
	for m in mat:
		mat[m] = mat[m] / total
	var G := level()
	var g := G - 1.0
	var cost_mult := {}
	var mean_share := 1.0 / maxf(1.0, mat.size())
	for m in DataDB.attributes()["materials"]:
		var pressure := clampf(1.0 + SEASON_PRESSURE_K * (float(mat.get(m, 0.0)) / mean_share - 1.0), SEASON_PRESSURE_MIN, SEASON_PRESSURE_MAX)
		cost_mult[m] = material_mult(m, period) * (1.0 + SUPPLY_G * g) * pressure
	return {
		"consumption_level": G,
		"G": G,
		"material_pref": mat,
		"wholesale_credit_risk": base["wholesale_credit_risk"],
		"loan_rate_base": base["loan_rate_base"],
		"price_level": price_level,
		"spending_power": pow(G, SPEND_ELASTICITY),
		"interest_rate": interest_rate(g),
		"freight_index": fuel_index_rw * (1.0 + FUEL_G * g) * float(SEASON_FUEL[Clock.SEASON_IDS[Clock.season_of(period)]]),
		"material_cost_mult": cost_mult,
		"credit_risk": float(base["wholesale_credit_risk"]) * (1.0 + CREDIT_RISK_G * maxf(0.0, -g)),
		"rent_index_target": rent_index_target,
	}


## 基准利率（年化）r = clamp(r0 + e_r·g + 0.5·(年化通胀 − 3%), 2%, 12%)（09 §1.3）。
func interest_rate(g: float) -> float:
	var annual := pow(1.0 + last_inflation, Clock.PERIODS_PER_YEAR) - 1.0
	return clampf(float(base["loan_rate_base"]) + RATE_G * g + 0.5 * (annual - 0.03), 0.02, 0.12)


## 某材质这一旬的供给冲击：随机游走 + 还在衰减中的事件，夹到 [0.7, 1.5]。
func material_mult(material: String, period: int) -> float:
	var v := float(material_shock.get(material, 1.0))
	for e in material_events:
		if e["material"] != material:
			continue
		var age := period - int(e["start"])
		var dur := int(e["duration"])
		if age >= 0 and age < dur:
			v += float(e["boost"]) * (1.0 - float(age) / dur)
	return clampf(v, SHOCK_MIN, SHOCK_MAX)


## 进入新的一旬：π、F_rw、M_m 与材质事件、租金目标往前走一步（09 §2）。
## g_prev 是刚结束那一旬的 g = G − 1（通胀看上一旬的景气）。
func period_step(period: int, g_prev: float, rng: GameRng) -> void:
	last_inflation = clampf(INFL_BASE + INFL_G * g_prev + rng.randfn(0.0, INFL_SD), INFL_MIN, INFL_MAX)
	price_level *= 1.0 + last_inflation
	fuel_index_rw = clampf(1.0 + FUEL_AR * (fuel_index_rw - 1.0) + rng.randfn(0.0, FUEL_SD), 0.7, 1.4)
	for m in DataDB.attributes()["materials"]:
		var prev := float(material_shock.get(m, 1.0))
		material_shock[m] = clampf(1.0 + SHOCK_AR * (prev - 1.0) + rng.randfn(0.0, SHOCK_SD), SHOCK_MIN, SHOCK_MAX)
	var alive: Array = []
	for e in material_events:
		if period - int(e["start"]) < int(e["duration"]):
			alive.append(e)
	material_events = alive
	if rng.chance(SHOCK_EVENT_P):
		var mats: Array = DataDB.attributes()["materials"].keys()
		material_events.append({"material": rng.pick(mats), "boost": SHOCK_EVENT_SIZE * (1.0 if rng.chance(0.5) else -1.0),
			"start": period, "duration": SHOCK_EVENT_LEN})
	g_history.append(g_prev)
	while g_history.size() > RENT_WINDOW:
		g_history.pop_front()
	var g_mean := 0.0
	for x in g_history:
		g_mean += float(x)
	g_mean /= g_history.size()
	rent_index_target = price_level * (1.0 + RENT_G * g_mean)


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
		"price_level": price_level,
		"last_inflation": last_inflation,
		"fuel_index_rw": fuel_index_rw,
		"material_shock": material_shock.duplicate(),
		"material_events": material_events.duplicate(true),
		"g_history": g_history.duplicate(),
		"rent_index_target": rent_index_target,
		"policy": policy.duplicate(true),
	}


static func from_dict(d: Dictionary) -> EconomyState:
	var e := EconomyState.new()
	var b: Dictionary = d.get("base", {})
	for k in b:
		e.base[k] = b[k]
	e.base_delta_history = d.get("base_delta_history", [])
	e.observations = d.get("observations", [])
	# 老存档里的 lambda / continuous_gain 不再读，以常量为准（09 §1.1 v0.2）
	e.price_level = float(d.get("price_level", 1.0))
	e.last_inflation = float(d.get("last_inflation", INFL_BASE))
	e.fuel_index_rw = float(d.get("fuel_index_rw", 1.0))
	e.material_shock = d.get("material_shock", {})
	e.material_events = d.get("material_events", [])
	e.g_history = d.get("g_history", [])
	e.rent_index_target = float(d.get("rent_index_target", e.price_level))
	var pol: Dictionary = d.get("policy", {})
	for k in pol:
		e.policy[k] = pol[k]
	return e
