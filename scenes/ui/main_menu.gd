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
	# 开店的资金门槛定下来之前，先从这里直接进开店阶段（07 §5）
	v.add_child(UIKit.button("试玩开店（预览）", func(): Game.new_preview_game(), 18))
	if Game.has_save(Game.PREVIEW_SAVE_PATH):
		v.add_child(UIKit.button("继续试玩开店", _continue_preview, 16))
	v.add_child(UIKit.button("调试界面", func(): Game.goto("debug"), 16))
	v.add_child(UIKit.button("退出", func(): get_tree().quit(), 16))
	_msg = UIKit.label("", 14, UIKit.BAD)
	v.add_child(_msg)


func _continue() -> void:
	var err := Game.continue_game()
	if err != "":
		_msg.text = "读档失败：" + err + "（原存档未改动）"


func _continue_preview() -> void:
	var err := Game.continue_game(Game.PREVIEW_SAVE_PATH)
	if err != "":
		_msg.text = "读档失败：" + err + "（原存档未改动）"
