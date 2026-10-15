extends TestCase


func test_period_math() -> void:
	assert_eq(Clock.season_of(1), 0)
	assert_eq(Clock.season_of(9), 0)
	assert_eq(Clock.season_of(10), 1)
	assert_eq(Clock.season_of(36), 3)
	assert_eq(Clock.season_of(37), 0)
	assert_eq(Clock.year_of(36), 1)
	assert_eq(Clock.year_of(37), 2)
	assert_eq(Clock.month_of(3), 1)
	assert_eq(Clock.month_of(4), 2)
	assert_true(Clock.is_month_end(3))
	assert_true(Clock.is_year_end(36))


func test_quality_master_toggle() -> void:
	var f := DifficultyFlags.new()
	assert_true(not f.set_flag("quality.mold", true), "总开关关闭时附属不能单独打开")
	f.set_flag("quality", true)
	for k in ["quality.mold", "quality.flatness", "quality.misweave", "quality.misdye"]:
		assert_true(f.is_on(k), k)
	f.set_flag("quality.mold", false)
	f.set_flag("quality.flatness", false)
	f.set_flag("quality.misweave", false)
	assert_true(f.is_on("quality"), "还剩一个附属时总开关仍开")
	f.set_flag("quality.misdye", false)
	assert_true(not f.is_on("quality"), "附属关到零个时总开关自动关闭")


func test_rng_roundtrip_through_json() -> void:
	var r := GameRng.new(123456789)
	r.randf()
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	var r2 := GameRng.from_dict(d)
	for i in 5:
		assert_eq(r.randf(), r2.randf())
