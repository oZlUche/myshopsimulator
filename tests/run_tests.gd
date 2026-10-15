extends SceneTree
## 运行：godot --headless --path . --script res://tests/run_tests.gd
## 发现 tests/unit/test_*.gd 并执行所有 test_ 方法；有失败时以退出码 1 结束。


func _init() -> void:
	var total := 0
	var failed: Array[String] = []
	var dir := DirAccess.open("res://tests/unit")
	var files: Array = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var inst: TestCase = script.new()
			inst._current = "%s::%s" % [f, name]
			inst.call(name)
			total += 1
			if inst.failures.is_empty():
				print("  ok   ", inst._current)
			else:
				print("  FAIL ", inst._current)
				failed.append_array(inst.failures)
	print("\n%d 个测试，%d 条失败" % [total, failed.size()])
	for msg in failed:
		print("  - ", msg)
	quit(1 if not failed.is_empty() or total == 0 else 0)
