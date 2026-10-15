class_name EventBus
extends RefCounted
## 事件总线（01 §4.8）。真相层状态变化在这里发信号；剧情 / 随机事件作为 IEventSource 挂上来。
## 现阶段只有总线与接口，没有任何事件内容。

signal event_emitted(kind: String, payload: Dictionary)

var _sources: Array = []


func emit(kind: String, payload: Dictionary = {}) -> void:
	event_emitted.emit(kind, payload)
	for s in _sources:
		s.on_event(kind, payload)


func register_source(source: IEventSource) -> void:
	_sources.append(source)
