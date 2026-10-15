class_name IEventSource
extends RefCounted
## 随机事件 / 剧情脚本的接口占位（01 §4.8）。可读真相层，只能通过 ActionAPI 改世界。


func on_event(_kind: String, _payload: Dictionary) -> void:
	pass


func on_period_start(_state) -> void:
	pass
