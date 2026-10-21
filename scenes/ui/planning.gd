extends Control
## 旬初规划（时间冻结，01 §3.1）：进货、整理行囊、买设备、标价、分配经验。

var s: GameState
var api: ActionAPI
var _header: Label
var _msg: Label
var _tabs: TabContainer
var _buy_box: VBoxContainer
var _bag_box: HBoxContainer
var _equip_box: VBoxContainer
var _price_box: VBoxContainer
var _skill_box: VBoxContainer
var _notes: RichTextLabel
var _selected := {"slot_id": "", "index": -1}


func _ready() -> void:
	s = Game.state
	api = ActionAPI.new(s)
	UIKit.background(self)
	var root := UIKit.vbox(8)
	UIKit.full_rect(root)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 12
	root.offset_bottom = -12
	add_child(root)

	_header = UIKit.label("", 20, UIKit.ACCENT)
	root.add_child(_header)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_buy_box = _tab("进货")
	var bag_tab := _tab("行囊与设备")
	_bag_box = UIKit.hbox(10)
	bag_tab.add_child(UIKit.label("行囊里的货（左键选中，再点“丢弃”）。行囊是软包，从中间拿也不会塌。", 14, UIKit.MUTED))
	bag_tab.add_child(_bag_box)
	bag_tab.add_child(UIKit.button("丢弃选中的货", _discard))
	bag_tab.add_child(UIKit.label("设备", 18, UIKit.ACCENT))
	_equip_box = UIKit.vbox(6)
	bag_tab.add_child(_equip_box)
	_price_box = _tab("标价")
	_skill_box = _tab("技能")
	var notes_tab := _tab("账本与预报")
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes.custom_minimum_size = Vector2(0, 420)
	notes_tab.add_child(_notes)

	var bar := UIKit.hbox(10)
	root.add_child(bar)
	_msg = UIKit.label("", 16, UIKit.GOOD)
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_msg)
	bar.add_child(UIKit.button("保存", _save))
	bar.add_child(UIKit.button("回主菜单", func(): Game.goto("menu")))
	if s.player.phase == "shop":
		bar.add_child(UIKit.button("去仓库 →", _go_room.bind("warehouse"), 20))
		bar.add_child(UIKit.button("去店里 →", _go_room.bind("shop"), 20))
	else:
		bar.add_child(UIKit.button("出门找摊位 →", _go_street, 20))
	_refresh()


func _tab(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	_tabs.add_child(scroll)
	var v := UIKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v


func _say(t: String, ok: bool = true) -> void:
	_msg.text = t
	_msg.add_theme_color_override("font_color", UIKit.GOOD if ok else UIKit.BAD)


func _refresh() -> void:
	_header.text = "%s　规划（时间暂停）　现金 %.1f 元　行囊空位 %d　未分配经验 %.0f" % [
		s.clock.label(), s.player.cash, api.bag_free_space(), s.player.xp_pool]
	_refresh_buy()
	_refresh_bag()
	_refresh_prices()
	_refresh_skills()
	_refresh_notes()


# ---------- 进货 ----------
func _refresh_buy() -> void:
	UIKit.clear(_buy_box)
	if s.player.phase == "shop":
		_buy_box.add_child(UIKit.label("开店以后按箱进货（托运部、批发市场）还没做。这一版先用仓库卸货区里的那批货：一箱 10 包，一包 10 条，有单色包也有混色包。", 14, UIKit.MUTED))
		return
	_buy_box.add_child(UIKit.label("本地围巾店今天的货。只看得到外观，看不出什么会流行。买的货直接装进行囊。", 14, UIKit.MUTED))
	for e in s.supplier_catalog:
		var row := UIKit.hbox(10)
		var sw := ColorRect.new()
		sw.color = UIKit.sku_color(e["sku_id"])
		sw.custom_minimum_size = Vector2(18, 18)
		row.add_child(sw)
		var name := UIKit.label(UIKit.sku_name(e["sku_id"]), 16)
		name.custom_minimum_size = Vector2(260, 0)
		row.add_child(name)
		row.add_child(UIKit.label("进价 %.1f 元" % e["unit_price"], 16))
		row.add_child(UIKit.label("余 %d" % e["stock"], 16, UIKit.MUTED))
		var qty := SpinBox.new()
		qty.min_value = 1
		qty.max_value = maxi(1, int(e["stock"]))
		qty.value = 1
		row.add_child(qty)
		var b := UIKit.button("买", func(): _buy(e, int(qty.value)))
		b.disabled = int(e["stock"]) <= 0
		row.add_child(b)
		_buy_box.add_child(row)


func _buy(e: Dictionary, qty: int) -> void:
	var r := api.purchase(e["sku_id"], qty, float(e["unit_price"]))
	if r["ok"]:
		_say("买了 %d 条%s。" % [qty, UIKit.sku_name(e["sku_id"])])
	else:
		_say("买不了：" + r["reason"], false)
	_refresh()


# ---------- 行囊与设备 ----------
func _refresh_bag() -> void:
	UIKit.clear(_bag_box)
	for sl in s.inventory.slots_of_type("Bag"):
		var v := StackView.new().setup(sl, "行囊 " + sl.id.trim_prefix("sl_"))
		if sl.id == _selected["slot_id"]:
			v.selected_index = _selected["index"]
		v.strip_pressed.connect(func(sid, i): _selected = {"slot_id": sid, "index": i}; _refresh_bag())
		v.strip_peek.connect(func(sid, i): api.peek_item(sid, i); _refresh_bag())
		_bag_box.add_child(v)
	UIKit.clear(_equip_box)
	if s.player.phase == "shop":
		_equip_box.add_child(UIKit.label("店面、仓库的设备到店里点「摆设备」、到仓库点「摆货架」，在格子上买、挪、卖。", 14, UIKit.MUTED))
		return
	for def_id in DataDB.equipment():
		var d: Dictionary = DataDB.equipment()[def_id]
		if d.get("phase") != "stall" or float(d.get("price", 0)) <= 0.0:
			continue
		var owned := 0
		for eid in s.inventory.equipment:
			if s.inventory.equipment[eid]["def_id"] == def_id:
				owned += 1
		var spec: Dictionary = d["provides_slots"][0]
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label("%s　%.0f 元　（+%d 个%s格，每格高 %d）已有 %d" % [
			d["name"], d["price"], spec["count"], "行囊" if spec["type"] == "Bag" else "摊位", spec["max_height"], owned], 16))
		var loc := "player" if spec["type"] == "Bag" else "stall"
		row.add_child(UIKit.button("购买", func(): _buy_equipment(def_id, loc)))
		_equip_box.add_child(row)


func _discard() -> void:
	if _selected["slot_id"] == "":
		_say("先在行囊里选中一份货。", false)
		return
	api.discard(_selected["slot_id"], _selected["index"])
	_selected = {"slot_id": "", "index": -1}
	_say("丢掉了一份货。")
	_refresh()


func _buy_equipment(def_id: String, loc: String) -> void:
	var r := api.buy_equipment(def_id, loc)
	_say("买好了。" if r["ok"] else "买不了：" + r.get("reason", ""), r["ok"])
	_refresh()


# ---------- 标价 ----------
func _refresh_prices() -> void:
	UIKit.clear(_price_box)
	_price_box.add_child(UIKit.label("给手上的每款货定个开价。客人会还价，开价太高会把人吓走，宰客还会让常客不再回来。", 14, UIKit.MUTED))
	var costs := {}
	var counts := {}
	for sl in s.inventory.slots.values():
		for it in sl.stack.items:
			costs[it.sku_id] = float(costs.get(it.sku_id, 0.0)) + float(it.provenance.get("unit_cost", 0.0))
			counts[it.sku_id] = int(counts.get(it.sku_id, 0)) + 1
	if counts.is_empty():
		_price_box.add_child(UIKit.label("手上还没有货。", 16))
	var ids := counts.keys()
	ids.sort()
	for sku_id in ids:
		var row := UIKit.hbox(10)
		var name := UIKit.label("%s ×%d" % [UIKit.sku_name(sku_id), counts[sku_id]], 16)
		name.custom_minimum_size = Vector2(300, 0)
		row.add_child(name)
		row.add_child(UIKit.label("平均进价 %.1f" % (costs[sku_id] / counts[sku_id]), 16, UIKit.MUTED))
		row.add_child(UIKit.label("开价", 16))
		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 9999
		sp.step = 1
		sp.value = float(s.stall["prices"].get(sku_id, DataDB.sku(sku_id)["base_price"]))
		sp.value_changed.connect(func(v): s.stall["prices"][sku_id] = v)
		row.add_child(sp)
		_price_box.add_child(row)


# ---------- 技能（02 §7.3：一技能一行，一级一段） ----------
func _refresh_skills() -> void:
	UIKit.clear(_skill_box)
	_skill_box.add_child(UIKit.label("经验是一个共用池，自己决定投到哪个技能的下一级。现在未分配：%.0f" % s.player.xp_pool, 16, UIKit.ACCENT))
	var flags := s.world_flags()
	for skill_id in DataDB.skills():
		var d: Dictionary = DataDB.skills()[skill_id]
		var row := UIKit.hbox(8)
		var name := UIKit.label(d["name"], 16)
		name.custom_minimum_size = Vector2(90, 0)
		row.add_child(name)
		var lv := s.player.skill_level(skill_id)
		var cap := int(d.get("phase_cap", {}).get(s.player.phase, 0))
		var invested := float(s.player.skills.get(skill_id, {}).get("invested", 0.0))
		for i in SkillSystem.max_level(skill_id):
			var cost := SkillSystem.cost_of(skill_id, i + 1)
			var f := 1.0 if i < lv else (invested / cost if i == lv else 0.0)
			var tip := "Lv%d　%.0f / %.0f 经验%s" % [i + 1, f * cost, cost, "" if i < cap else "（开店后解锁）"]
			row.add_child(SegmentBar.new().setup(f, i < lv, i >= cap, tip))
		var reason := SkillSystem.lock_reason(s.player, skill_id, flags)
		if reason == "":
			row.add_child(UIKit.button("+10", func(): _invest(skill_id, 10.0)))
			row.add_child(UIKit.button("投满下一级", func(): _invest(skill_id, INF)))
		else:
			row.add_child(UIKit.label(reason, 14, UIKit.MUTED))
		_skill_box.add_child(row)


func _invest(skill_id: String, amount: float) -> void:
	var before := s.player.skill_level(skill_id)
	var put := SkillSystem.invest(s.player, skill_id, amount, s.world_flags())
	if put <= 0.0:
		_say("经验不够了。", false)
	elif s.player.skill_level(skill_id) > before:
		_say("%s 升到 Lv%d！" % [DataDB.skills()[skill_id]["name"], s.player.skill_level(skill_id)])
	_refresh()


# ---------- 账本与预报 ----------
func _refresh_notes() -> void:
	var t := "[b]审美积累的预报[/b]\n"
	if s.knowledge.trend_hints.is_empty():
		t += "（还没有。学了审美积累后，旬末有机会得知接下来会流行什么。）\n"
	for h in s.knowledge.trend_hints.slice(-8):
		t += "第 %d 旬：%s\n" % [h["period"], h["text"]]
	t += "\n[b]最近的账[/b]（自己的流水，只记你知道的事）\n"
	for e in s.knowledge.ledger.slice(-20):
		t += "第 %d 旬　%s　%+.1f　%s\n" % [e["period"], {"purchase": "进货", "sale": "卖出", "discard": "丢弃", "equipment": "设备"}.get(e["kind"], e["kind"]), e["amount"], e["note"]]
	_notes.text = t


func _save() -> void:
	var r := Game.autosave()
	_say("已保存。" if r["ok"] else "保存失败：" + r["error"], r["ok"])


## 开店阶段：去店里或去仓库（07）。
func _go_room(scene: String) -> void:
	Game.autosave()
	Game.arrive_from = "planning"
	Game.goto(scene)


func _go_street() -> void:
	if s.inventory.count_items("player", "Bag") == 0 and s.inventory.count_items("", "StallTable") == 0:
		_say("行囊是空的，先进点货吧。", false)
		return
	Game.autosave()
	Game.goto("street")
