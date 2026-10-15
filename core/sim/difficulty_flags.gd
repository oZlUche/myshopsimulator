class_name DifficultyFlags
extends RefCounted
## 进阶难度开关（04 文档）。层级联动全部在 set_flag() 里处理，UI 不写规则。

const PARENTS := {
	"quality.mold": "quality",
	"quality.flatness": "quality",
	"quality.misweave": "quality",
	"quality.misdye": "quality",
}
const ALL_FLAGS := [
	"quality", "quality.mold", "quality.flatness", "quality.misweave", "quality.misdye",
	"manual_checkout", "employee_embezzlement", "wholesale_late_payment",
]

var _values: Dictionary = {}


func _init() -> void:
	for f in ALL_FLAGS:
		_values[f] = false


func is_on(flag_id: String) -> bool:
	return bool(_values.get(flag_id, false))


func children_of(parent_id: String) -> Array:
	var out: Array = []
	for c in PARENTS:
		if PARENTS[c] == parent_id:
			out.append(c)
	return out


## 返回是否成功改变。规则见 04 §1。
func set_flag(flag_id: String, on: bool) -> bool:
	if not _values.has(flag_id):
		return false
	var kids := children_of(flag_id)
	if not kids.is_empty():
		# 总开关：打开 => 附属全开；关闭 => 附属全关。
		_values[flag_id] = on
		for k in kids:
			_values[k] = on
		return true
	if PARENTS.has(flag_id):
		var parent: String = PARENTS[flag_id]
		if on and not is_on(parent):
			return false  # 附属开关不能在总开关关闭时单独打开
		_values[flag_id] = on
		if not on:
			var any_on := false
			for k in children_of(parent):
				any_on = any_on or is_on(k)
			if not any_on:
				_values[parent] = false  # 关到零个时总开关自动关闭
		return true
	_values[flag_id] = on
	return true


func to_dict() -> Dictionary:
	return _values.duplicate()


static func from_dict(d: Dictionary) -> DifficultyFlags:
	var f := DifficultyFlags.new()
	for k in d:
		f._values[k] = bool(d[k])
	return f
