extends Node
## 全局流程控制（表现层，自动加载为 Game）。持有当前 GameState，负责场景切换与存档。
## 流程：主菜单 → 规划（时间冻结）→ 街区选址 → 摆摊营业 → 旬末结算 → 规划 …
## 开店以后（07）：规划 → 店面 ⇄ 仓库 → 旬末结算 → 规划 …

const SAVE_PATH := "user://save_slot_1.json"
## "试玩开店（预览）"单独一个存档，不碰正式存档
const PREVIEW_SAVE_PATH := "user://save_preview.json"
const SCENES := {
	"menu": "res://scenes/ui/main_menu.tscn",
	"planning": "res://scenes/ui/planning.tscn",
	"street": "res://scenes/stall/street.tscn",
	"stall": "res://scenes/stall/stall.tscn",
	"settlement": "res://scenes/ui/settlement.tscn",
	"shop": "res://scenes/shop/shop.tscn",
	"warehouse": "res://scenes/shop/warehouse.tscn",
	"debug": "res://scenes/debug/debug_main.tscn",
}

var state: GameState
var saver := SaveManager.new()
var save_path := SAVE_PATH
## 街区里选定的摊位位置
var stall_x: float = 0.0
## 上一旬结算报告
var last_report: Dictionary = {}
## 时间流速（设置项，01 §3.1）
var time_scale: float = 1.0
## 从哪来的（planning / shop / warehouse）：进店面、仓库时人站在门口还是收银台后
var arrive_from := ""
## 这一旬还没回来的常客：店面和仓库来回跑时接着用，同一个常客一旬只回来一次
var _returning: Array[CustomerProfile] = []
var _returning_period := -1


func new_game(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system())
	state = GameState.new_game(seed_value)
	saver = SaveManager.new()
	save_path = SAVE_PATH
	PeriodRunner.begin_period(state)
	autosave()
	goto("planning")


## 试玩开店（07 §5）：直接进开店阶段，已租店面和仓库，卸货区有 6 箱货。存在单独的预览存档里。
func new_preview_game(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system())
	state = GameState.new_game(seed_value)
	saver = SaveManager.new()
	save_path = PREVIEW_SAVE_PATH
	PeriodRunner.begin_period(state)
	ShopSetup.start_preview(state)
	autosave()
	goto("planning")


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## 读档；返回错误信息，成功为空字符串。
func continue_game(path: String = SAVE_PATH) -> String:
	var s := SaveManager.new()
	var r := s.load_game(path)
	if not r["ok"]:
		return r["error"]
	saver = s
	state = r["state"]
	save_path = path
	goto("planning")
	return ""


func returning_for(s: GameState) -> Array[CustomerProfile]:
	if _returning_period != s.clock.period:
		_returning_period = s.clock.period
		_returning = s.customers.roll_returning(s.rng)
	return _returning


func keep_returning(left: Array[CustomerProfile]) -> void:
	_returning = left.duplicate()


## 只在规划阶段（时间冻结）存档。
func autosave() -> Dictionary:
	if state == null:
		return {"ok": false, "error": "没有进行中的游戏"}
	return saver.save_game(state, save_path)


func goto(scene: String) -> void:
	get_tree().change_scene_to_file.call_deferred(SCENES[scene])


## 旬末：收摊 → 结算 → 下一旬开始并自动存档。
func end_period(report_extra: Dictionary = {}) -> void:
	last_report = PeriodRunner.end_period(state)
	last_report.merge(report_extra)
	PeriodRunner.begin_period(state)
	autosave()
	goto("settlement")
