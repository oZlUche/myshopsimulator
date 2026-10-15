extends Control
## 调试主界面（阶段 0 临时入口）。直接显示真相层数据，仅供开发验证；正式场景只读认知层。
## 摆摊街区 / 摊位 / 议价 / 抽取小游戏场景会逐步替换这里。

const SAVE_PATH := "user://save_slot_1.json"

var state: GameState
var api: ActionAPI
var saver := SaveManager.new()

var _status: Label
var _catalog: VBoxContainer
var _slots: RichTextLabel
var _log: RichTextLabel


func _ready() -> void:
	_build_ui()
	_new_game()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_status = Label.new()
	root.add_child(_status)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	for spec in [
		["新游戏", _new_game], ["自动进货并摆摊", _auto_prepare], ["自动经营一旬", _simulate_period],
		["保存", _save], ["读取", _load],
	]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		buttons.add_child(b)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	body.add_child(left)
	var t := Label.new()
	t.text = "本地进货店（本旬目录）"
	left.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_catalog = VBoxContainer.new()
	scroll.add_child(_catalog)

	_slots = RichTextLabel.new()
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots.bbcode_enabled = true
	body.add_child(_slots)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 200)
	_log.scroll_following = true
	root.add_child(_log)


func _new_game() -> void:
	state = GameState.new_game(int(Time.get_unix_time_from_system()))
	saver = SaveManager.new()
	PeriodRunner.begin_period(state)
	_bind()
	_say("新的一局开始了。你只有一个随身大包和一块地摊布。")


func _bind() -> void:
	api = ActionAPI.new(state)
	_refresh()


func _auto_prepare() -> void:
	AutoSeller.auto_prepare(state)
	_say("自动进货并把行囊里的货摆上了地摊布。")
	_refresh()


func _simulate_period() -> void:
	var label := state.clock.label()
	var r := AutoSeller.simulate_stall_period(state)
	_say("%s：客流 %d，逗留 %d，成交 %d，营业额 %.1f，倒塌 %d 次，收摊丢弃 %d 件。" % [
		label, r["traffic"], r["stayed"], r["sales"], r["revenue"], r["collapses"], r["lost_on_pack_up"]])
	for f in r["forecasts"]:
		_say("  审美积累：" + f["text"])
	if r["season_changed"]:
		_say("  换季了：%s" % Clock.SEASON_NAMES[state.clock.season()])
	PeriodRunner.begin_period(state)
	_refresh()


func _buy(sku_id: String, price: float) -> void:
	var r := api.purchase(sku_id, 1, price)
	if not r["ok"]:
		_say("买不了：" + r["reason"])
	_refresh()


func _save() -> void:
	var r := saver.save_game(state, SAVE_PATH)
	_say("已保存到 %s" % ProjectSettings.globalize_path(SAVE_PATH) if r["ok"] else "保存失败：" + r["error"])


func _load() -> void:
	var r := saver.load_game(SAVE_PATH)
	if not r["ok"]:
		_say("读取失败：" + r["error"])
		return
	state = r["state"]
	_bind()
	_say("读档成功（存档版本 %d）。" % r["migrated_from"])


func _refresh() -> void:
	_status.text = "%s    现金 %.1f    未分配经验 %.1f    阶段：%s" % [
		state.clock.label(), state.player.cash, state.player.xp_pool, "摆摊" if state.player.phase == "stall" else "开店"]
	for c in _catalog.get_children():
		c.queue_free()
	for e in state.supplier_catalog:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s  %.1f元  余%d" % [DataDB.sku_display_name(e["sku_id"]), e["unit_price"], e["stock"]]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.text = "买 1"
		b.disabled = int(e["stock"]) <= 0
		b.pressed.connect(_buy.bind(e["sku_id"], float(e["unit_price"])))
		row.add_child(b)
		_catalog.add_child(row)
	var txt := "[b]槽位（调试：显示真相层，底 → 顶）[/b]\n"
	for type in ["Bag", "StallTable"]:
		for sl in state.inventory.slots_of_type(type):
			var names: Array = sl.stack.items.map(func(i): return DataDB.sku_display_name(i.sku_id))
			txt += "%s %s [%d/%d] 乱%.2f：%s\n" % [
				"行囊" if type == "Bag" else "摊位", sl.id, sl.stack.height(), sl.stack.max_height,
				sl.stack.disorder, "、".join(names) if not names.is_empty() else "（空）"]
	_slots.text = txt


func _say(msg: String) -> void:
	_log.append_text(msg + "\n")
