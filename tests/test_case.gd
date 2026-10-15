class_name TestCase
extends RefCounted
## 极简单元测试基类：方法名以 test_ 开头即被执行。不依赖 GUT 等插件，方便 CI 直接跑。

var failures: Array[String] = []
var _current := ""


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("%s: 断言失败 %s" % [_current, msg])


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		failures.append("%s: 期望 %s，实际 %s %s" % [_current, str(b), str(a), msg])


func assert_near(a: float, b: float, eps: float = 0.0001, msg: String = "") -> void:
	if absf(a - b) > eps:
		failures.append("%s: 期望 %f ≈ %f %s" % [_current, a, b, msg])
