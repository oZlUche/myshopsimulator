extends SceneTree
## 生成当前 schema 版本的存档 fixture：
##   godot --headless --path . --script res://tests/tools/make_fixture.gd
## 每次提升 SaveManager.CURRENT_SCHEMA_VERSION 都要跑一次并提交生成的文件（01 §7.1 第 6 条）。


func _init() -> void:
	var s := GameState.new_game(2026)
	PeriodRunner.begin_period(s)
	AutoSeller.auto_prepare(s)
	AutoSeller.simulate_stall_period(s)
	PeriodRunner.begin_period(s)
	var path := "res://tests/save_fixtures/v%04d.json" % SaveManager.CURRENT_SCHEMA_VERSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(s.to_dict(), "\t"))
	f.close()
	print("wrote ", path)
	quit(0)
