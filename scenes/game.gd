extends Node
## 全局流程控制（表现层，自动加载为 Game）。持有当前 GameState，负责场景切换与存档。
## 流程：主菜单 → 规划（时间冻结）→ 街区选址 → 摆摊营业 → 旬末结算 → 规划 …

const SAVE_PATH := "user://save_slot_1.json"
const SCENES := {
	"menu": "res://scenes/ui/main_menu.tscn",
	"planning": "res://scenes/ui/planning.tscn",
	"street": "res://scenes/stall/street.tscn",
	"stall": "res://scenes/stall/stall.tscn",
	"settlement": "res://scenes/ui/settlement.tscn",
	"debug": "res://scenes/debug/debug_main.tscn",
}

var state: GameState
var saver := SaveManager.new()
## 街区里选定的摊位位置
var stall_x: float = 0.0
## 上一旬结算报告
var last_report: Dictionary = {}
## 时间流速（设置项，01 §3.1）
var time_scale: float = 1.0


func new_game(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system())
	state = GameState.new_game(seed_value)
	saver = SaveManager.new()
	PeriodRunner.begin_period(state)
	autosave()
	goto("planning")


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 读档；返回错误信息，成功为空字符串。
func continue_game() -> String:
	var s := SaveManager.new()
	var r := s.load_game(SAVE_PATH)
	if not r["ok"]:
		return r["error"]
	saver = s
	state = r["state"]
	goto("planning")
	return ""


## 只在规划阶段（时间冻结）存档。
func autosave() -> Dictionary:
	if state == null:
		return {"ok": false, "error": "没有进行中的游戏"}
	return saver.save_game(state, SAVE_PATH)


func goto(scene: String) -> void:
	get_tree().change_scene_to_file.call_deferred(SCENES[scene])


## 旬末：收摊 → 结算 → 下一旬开始并自动存档。
func end_period(report_extra: Dictionary = {}) -> void:
	last_report = PeriodRunner.end_period(state)
	last_report.merge(report_extra)
	PeriodRunner.begin_period(state)
	autosave()
	goto("settlement")
