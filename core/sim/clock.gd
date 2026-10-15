class_name Clock
extends RefCounted
## 时间轴：旬（period）从 1 起。3 旬 = 1 月，9 旬 = 1 季，36 旬 = 1 年。见 01 §3.0。

const PERIODS_PER_MONTH := 3
const PERIODS_PER_SEASON := 9
const PERIODS_PER_YEAR := 36
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]
const SEASON_NAMES := ["春", "夏", "秋", "冬"]

var period: int = 1
## 旬内时间进度 0..1（只在营业 / 开车 / 仓库作业时推进）。
var time_of_period: float = 0.0


static func season_of(p: int) -> int:
	return ((p - 1) % PERIODS_PER_YEAR) / PERIODS_PER_SEASON


static func year_of(p: int) -> int:
	return (p - 1) / PERIODS_PER_YEAR + 1


static func month_of(p: int) -> int:
	return ((p - 1) % PERIODS_PER_YEAR) / PERIODS_PER_MONTH + 1


## 本旬是否为月末（结算租金 / 工资 / 贷款）。
static func is_month_end(p: int) -> bool:
	return p % PERIODS_PER_MONTH == 0


static func is_year_end(p: int) -> bool:
	return p % PERIODS_PER_YEAR == 0


func season() -> int:
	return season_of(period)


func year() -> int:
	return year_of(period)


func label() -> String:
	var idx_in_month := (period - 1) % PERIODS_PER_MONTH
	return "第%d年 %d月%s旬（%s）" % [year(), month_of(period), ["上", "中", "下"][idx_in_month], SEASON_NAMES[season()]]


func to_dict() -> Dictionary:
	return {"period": period, "time_of_period": time_of_period}


static func from_dict(d: Dictionary) -> Clock:
	var c := Clock.new()
	c.period = int(d.get("period", 1))
	c.time_of_period = float(d.get("time_of_period", 0.0))
	return c
