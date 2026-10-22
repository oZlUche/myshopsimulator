class_name EconomyState
extends RefCounted
## 真相层：双循环宏观经济（01 §4.2）。E(t) = Base(year) + C(t) + Season(t)。
## Base 只读年度 Δ 历史；C 只读最近 ≤36 旬观测；两者互不读取，最后相加。
## 景气 G = Base + C 是主驱动，物价 π、运力 F、材质供给冲击 M_m 等宏观状态每旬由 period_step 更新（09 §1、§2）。

const OBS_WINDOW := 36
## 连续循环 C（09 §1.1 v0.3）：每维观测相对自己基线（窗口里除去最近 6 旬的均值）的偏离，按 λ 衰减加权，× 增益后夹到 ±C_MAX；基线不足 C_MIN_OBS 旬时为 0
const LAMBDA := 0.88
const C_GAIN := 0.2
const C_MAX := 0.15
## 基线不含最近 C_RECENT 旬（09 §1.1 v0.3），否则好转的那几旬会把自己的偏离摊薄
const C_RECENT := 6
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
## 节拍层 B（09 §1.8）：季节需求 · 日历事件 · 突发天气，固定部分年均归一到 1，只乘客流和购物意向
const SEASON_D_AMP := 0.35
const SEASON_D_PEAK := 32
const B_MIN := 0.6
const B_MAX := 1.6
## 日历事件（按年内旬号 q = 1..36）：{name, q: {q: [客流倍率, 意向加成]}}；集市日另算（每月下旬）
const CALENDAR := [
	{"name": "年关抢购", "q": {34: [1.25, 0.10], 35: [1.45, 0.15], 36: [1.6, 0.20]}},
	{"name": "年初清淡", "q": {1: [0.6, -0.05], 2: [0.8, -0.05]}},
	{"name": "开春集", "q": {4: [1.3, 0.05]}},
	{"name": "长假", "q": {19: [1.3, 0.05], 20: [1.2, 0.05]}},
	{"name": "丰收季", "q": {22: [1.1, 0.05], 23: [1.1, 0.05], 24: [1.1, 0.05], 25: [1.1, 0.05], 26: [1.1, 0.05], 27: [1.1, 0.05]}},
]
const MARKET_DAY := [1.15, 0.0]
## 突发天气：触发的年内旬号范围、每旬概率、客流倍率、意向加成、持续旬数（线性衰减到 1）；indoor = 店里受影响的比例
const WEATHER := {
	"cold": {"name": "突然降温", "tip": "突然冷了，来买围巾的人多", "tip_later": "还冷着，来买围巾的人还多", "q": [[19, 36], [1, 3]], "p": 0.10, "mult": 1.3, "intent": 0.1, "duration": 2, "indoor": 1.0},
	"warm": {"name": "冬天回暖", "tip": "回暖了，没什么人想买围巾", "tip_later": "还暖和着，买围巾的人少", "q": [[28, 36]], "p": 0.06, "mult": 0.85, "intent": 0.0, "duration": 2, "indoor": 1.0},
	"rain": {"name": "连着下雨", "tip": "连着下雨，街上人少（店里好一点）", "q": [[10, 18]], "p": 0.12, "mult": 0.75, "intent": 0.0, "duration": 1, "indoor": 0.5},
	"sand": {"name": "大风沙", "tip": "刮大风沙，出门的人少，出来的更想买", "q": [[1, 9]], "p": 0.05, "mult": 0.8, "intent": 0.05, "duration": 1, "indoor": 1.0},
}
## 年关抢购从年内第 34 旬（12 月上旬）开始
const YEAR_END_RUSH_Q := 34

## 年度基准（每 36 旬随机调整一次）。material_bias 为对季节基线的偏移。
var base: Dictionary = {
	"consumption_level": 1.0,
	"material_bias": {},
	"wholesale_credit_risk": 0.1,
	"loan_rate_base": 0.05,
}
## 每年一条：{"consumption_level": Δ}
var base_delta_history: Array = []
## 节拍层的突发天气（09 §1.8）：[{kind, start, duration, traffic_mult, intent_add}]，同 material_events 的形式
var rhythm_events: Array = []
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


## 连续循环 C(t)（09 §1.1 v0.3）：只看"最近比自己过去好还是差"。每维观测减去基线（窗口 ≤36 旬里除去最近 6 旬的等权均值），
## 除以显著单位，三维加权成 dev，再按 λ^i 衰减加权平均，× C_GAIN，夹到 ±C_MAX。玩家一贯卖得便宜或贵不会改变 G；
## 好转持续满一个窗口后基线跟上，C 回零。基线不足 4 旬（开局前 10 旬）时 C = 0。
func continuous_term() -> float:
	var n: int = mini(observations.size(), OBS_WINDOW)
	var base_n := n - C_RECENT
	if base_n < C_MIN_OBS:
		return 0.0
	var recent := observations.slice(observations.size() - n)
	var mean := {}
	for k in DEV_WEIGHT:
		var sum := 0.0
		for j in base_n:
			sum += float(recent[j].get(k, 0.0))
		mean[k] = sum / base_n
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
		"rhythm_mult": rhythm(period, false),
		"rhythm_mult_indoor": rhythm(period, true),
		"rhythm_intent_add": rhythm_intent(period),
		"calendar_events": calendar_names(period),
		"weather_events": weather_names(period),
	}


# ---------- 节拍层 B（09 §1.8） ----------
## 年内旬号 q = 1..36。
static func year_q(period: int) -> int:
	return (period - 1) % Clock.PERIODS_PER_YEAR + 1


## 季节需求：峰在 11 月中（q = 32）1.35，谷在 5 月中 0.65，一年均值 1。
static func season_demand(q: int) -> float:
	return 1.0 + SEASON_D_AMP * cos(TAU * float(q - SEASON_D_PEAK) / Clock.PERIODS_PER_YEAR)


## 日历事件在第 q 旬的 [客流倍率, 意向加成, 事件名列表]（固定、按年循环）。
static func calendar(q: int) -> Array:
	var mult := 1.0
	var intent := 0.0
	var names: Array = []
	for ev in CALENDAR:
		if ev["q"].has(q):
			mult *= float(ev["q"][q][0])
			intent += float(ev["q"][q][1])
			names.append(ev["name"])
	if q % Clock.PERIODS_PER_MONTH == 0:
		mult *= float(MARKET_DAY[0])
		intent += float(MARKET_DAY[1])
		names.append("集市日")
	return [mult, intent, names]


static var _rhythm_norm := 0.0


## 归一化 Z（只算一次）：让夹限后的固定部分 clamp(季节需求 × 日历 / Z) 一年 36 旬均值正好 1。
## 不夹限的均值是 1.119，但年关最后两旬会顶到 1.6，直接除会让年均掉到 0.985，所以二分找 Z（≈ 1.099）。
static func rhythm_norm() -> float:
	if _rhythm_norm <= 0.0:
		var lo := 0.5
		var hi := 2.0
		for i in 50:
			var z := (lo + hi) / 2.0
			var sum := 0.0
			for q in range(1, Clock.PERIODS_PER_YEAR + 1):
				sum += clampf(season_demand(q) * float(calendar(q)[0]) / z, B_MIN, B_MAX)
			if sum / Clock.PERIODS_PER_YEAR > 1.0:
				lo = z
			else:
				hi = z
		_rhythm_norm = (lo + hi) / 2.0
	return _rhythm_norm


## 突发天气在这一旬的 [客流倍率, 意向加成]：同类不叠，不同类相乘；按开始后的旬数线性衰减到 1。
func weather(period: int, indoor := false) -> Array:
	var mult := 1.0
	var intent := 0.0
	for e in rhythm_events:
		var age := period - int(e["start"])
		var dur := int(e["duration"])
		if age < 0 or age >= dur:
			continue
		var f := 1.0 - float(age) / dur
		var share := float(WEATHER.get(e["kind"], {}).get("indoor", 1.0)) if indoor else 1.0
		mult *= 1.0 + (float(e["traffic_mult"]) - 1.0) * f * share
		intent += float(e["intent_add"]) * f
	return [mult, intent]


## B(t)：乘在过路客 / 进店密度上（09 §1.8）。indoor = 店面（雨天影响减半）。
func rhythm(period: int, indoor := false) -> float:
	var q := year_q(period)
	var fixed := season_demand(q) * float(calendar(q)[0])
	return clampf(fixed * float(weather(period, indoor)[0]) / rhythm_norm(), B_MIN, B_MAX)


## 购物意向加成：日历 + 天气。
func rhythm_intent(period: int) -> float:
	return float(calendar(year_q(period))[1]) + float(weather(period)[1])


static func calendar_names(period: int) -> Array:
	return calendar(year_q(period))[2]


func weather_names(period: int) -> Array:
	var out: Array = []
	for e in rhythm_events:
		var age := period - int(e["start"])
		if age >= 0 and age < int(e["duration"]):
			out.append(WEATHER.get(e["kind"], {}).get("name", e["kind"]))
	return out


## 当旬天气提示（09 §1.8：天气只在发生当旬告诉玩家）。没有天气返回 ""。
func weather_notice(period: int) -> String:
	var tips: Array = []
	for e in rhythm_events:
		var age := period - int(e["start"])
		if age >= 0 and age < int(e["duration"]):
			var w: Dictionary = WEATHER.get(e["kind"], {})
			tips.append(str(w.get("tip_later" if age > 0 and w.has("tip_later") else "tip", w.get("name", e["kind"]))))
	return "；".join(tips)


## 规划页的日历（固定、公开）：本月和下月的事件、离年关还有几旬、本旬行情冷热。
static func calendar_outlook(period: int) -> String:
	var parts: Array = []
	var month_start := period - (period - 1) % Clock.PERIODS_PER_MONTH
	for m in 2:
		var first := month_start + m * Clock.PERIODS_PER_MONTH
		var by_name := {}
		for i in Clock.PERIODS_PER_MONTH:
			if first + i < period:
				continue
			for n in calendar_names(first + i):
				if not by_name.has(n):
					by_name[n] = []
				by_name[n].append(["上", "中", "下"][i])
		var items: Array = []
		for n in by_name:
			items.append("%s（%s旬）" % [n, "、".join(by_name[n])])
		parts.append("%s %d月：%s" % [["本月", "下月"][m], Clock.month_of(first), "、".join(items) if not items.is_empty() else "没什么事"])
	var q := year_q(period)
	if q >= YEAR_END_RUSH_Q:
		parts.append("年关抢购中")
	else:
		parts.append("再过 %d 旬年关" % (YEAR_END_RUSH_Q - q))
	var fixed := clampf(season_demand(q) * float(calendar(q)[0]) / rhythm_norm(), B_MIN, B_MAX)
	var word := "很旺" if fixed >= 1.3 else ("偏旺" if fixed >= 1.1 else ("平常" if fixed >= 0.9 else ("偏淡" if fixed >= 0.7 else "很淡")))
	parts.append("本旬围巾行情%s" % word)
	return "　".join(parts)


## 新的一旬掷一次突发天气：在季节范围内、同类没在生效，就按概率触发。
func _roll_weather(period: int, rng: GameRng) -> void:
	var alive: Array = []
	for e in rhythm_events:
		if period - int(e["start"]) < int(e["duration"]):
			alive.append(e)
	rhythm_events = alive
	var q := year_q(period)
	for kind in WEATHER:
		var w: Dictionary = WEATHER[kind]
		var in_season := false
		for r in w["q"]:
			in_season = in_season or (q >= int(r[0]) and q <= int(r[1]))
		if not in_season or rhythm_events.any(func(e): return e["kind"] == kind):
			continue
		if rng.chance(float(w["p"])):
			rhythm_events.append({"kind": kind, "start": period, "duration": int(w["duration"]),
				"traffic_mult": float(w["mult"]), "intent_add": float(w["intent"])})


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
	_roll_weather(period, rng)
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
		"rhythm_events": rhythm_events.duplicate(true),
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
	e.rhythm_events = d.get("rhythm_events", [])
	e.g_history = d.get("g_history", [])
	e.rent_index_target = float(d.get("rent_index_target", e.price_level))
	var pol: Dictionary = d.get("policy", {})
	for k in pol:
		e.policy[k] = pol[k]
	return e
