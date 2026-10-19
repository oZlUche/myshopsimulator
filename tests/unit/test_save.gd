extends TestCase

const FAKE := {
	1: preload("res://tests/helpers/m_fake_0001_to_0002.gd"),
	2: preload("res://tests/helpers/m_fake_0002_to_0003.gd"),
}


## JSON 里不分整数和浮点（读回来都是浮点），比较前先统一走一遍 JSON。
func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


func _played_state() -> GameState:
	var s := GameState.new_game(99)
	PeriodRunner.begin_period(s)
	AutoSeller.auto_prepare(s)
	AutoSeller.simulate_stall_period(s)
	PeriodRunner.begin_period(s)
	return s


func test_roundtrip_is_lossless() -> void:
	var s := _played_state()
	var a := s.to_dict()
	var text := JSON.stringify(a)
	var sm := SaveManager.new()
	var r := sm.load_from_string(text)
	assert_true(r["ok"], str(r.get("error", "")))
	var b: Dictionary = r["state"].to_dict()
	assert_eq(_norm(b), _norm(JSON.parse_string(text)), "存档 → 读档 → 存档 应完全一致")


func test_unknown_fields_are_preserved() -> void:
	var s := GameState.new_game(1)
	var d := s.to_dict()
	d["mod_data"] = {"x": 1}
	d["player"]["future_field"] = "keep me"
	var sm := SaveManager.new()
	var r := sm.load_from_string(JSON.stringify(d))
	assert_true(r["ok"])
	var merged := SaveManager.deep_merge(sm._raw, r["state"].to_dict())
	assert_eq(_norm(merged.get("mod_data")), _norm({"x": 1}))
	assert_eq(merged["player"].get("future_field"), "keep me")


func test_removed_collection_entries_stay_removed() -> void:
	var old := {"knowledge": {"labels": {"sl_1": "红围巾", "sl_2": "旧"}}}
	var fresh := {"knowledge": {"labels": {"sl_1": "红围巾"}}}
	var merged := SaveManager.deep_merge(old, fresh)
	assert_true(not merged["knowledge"]["labels"].has("sl_2"), "集合里删掉的条目不应被旧档复活")


func test_migration_chain_runs_in_order() -> void:
	var d := {"schema_version": 1, "player": {"cash": 321.0}}
	var r := SaveManager.migrate(d, FAKE, 3)
	assert_true(r["ok"])
	assert_eq(r["data"]["schema_version"], 3)
	assert_eq(r["data"]["player"]["money"], 321.0)
	assert_eq(r["data"]["player"]["stamina"], 100.0)
	assert_eq(r["migrated_from"], 1)


func test_missing_migration_fails_safely() -> void:
	var r := SaveManager.migrate({"schema_version": 1}, {}, 2)
	assert_true(not r["ok"])


func test_newer_save_is_refused() -> void:
	var r := SaveManager.migrate({"schema_version": SaveManager.CURRENT_SCHEMA_VERSION + 1}, {})
	assert_true(not r["ok"], "更新版本的存档必须拒绝而不是乱读")


func test_save_writes_backup() -> void:
	var path := "user://test_save_slot.json"
	var sm := SaveManager.new()
	var s := GameState.new_game(5)
	assert_true(sm.save_game(s, path)["ok"])
	s.player.cash = 1.0
	assert_true(sm.save_game(s, path)["ok"])
	assert_true(FileAccess.file_exists(path + ".bak"), "第二次写档应留下 .bak")
	var r := SaveManager.new().load_game(path)
	assert_near(r["state"].player.cash, 1.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))


## 01 §7.1 第 6 条：每个历史版本的存档都要能迁移到当前版本并正常跑一旬。
func test_all_fixtures_load_and_play_a_period() -> void:
	var dir := DirAccess.open("res://tests/save_fixtures")
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		n += 1
		var r := SaveManager.new().load_game("res://tests/save_fixtures/" + f)
		assert_true(r["ok"], "%s: %s" % [f, r.get("error", "")])
		if not r["ok"]:
			continue
		var s: GameState = r["state"]
		var p := s.clock.period
		AutoSeller.auto_prepare(s)
		var rep := AutoSeller.simulate_stall_period(s)
		assert_eq(s.clock.period, p + 1, f)
		assert_true(int(rep["traffic"]) > 0, f + " 应有过路客")
	assert_true(n >= 1, "至少要有一份 fixture")
