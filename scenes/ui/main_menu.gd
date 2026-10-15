extends Control

var _msg: Label


func _ready() -> void:
	UIKit.background(self)
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	add_child(center)
	var v := UIKit.vbox(14)
	center.add_child(v)
	v.add_child(UIKit.label("围巾店模拟器", 40, UIKit.ACCENT))
	v.add_child(UIKit.label("阶段 0 · 摆摊（占位美术）", 16, UIKit.MUTED))
	v.add_child(UIKit.button("新游戏", func(): Game.new_game(), 22))
	var cont := UIKit.button("继续", _continue, 22)
	cont.disabled = not Game.has_save()
	v.add_child(cont)
	v.add_child(UIKit.button("调试界面", func(): Game.goto("debug"), 16))
	v.add_child(UIKit.button("退出", func(): get_tree().quit(), 16))
	_msg = UIKit.label("", 14, UIKit.BAD)
	v.add_child(_msg)


func _continue() -> void:
	var err := Game.continue_game()
	if err != "":
		_msg.text = "读档失败：" + err + "（原存档未改动）"
