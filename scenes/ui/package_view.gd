class_name PackageView
extends Control
## 画一个槽位里的整箱整包（07 §1）：从下往上堆，只有最上面那个能动。
## 箱子外面只看得到物流单和你写的标签；拆开的箱子掀开盖，看得到每包最上面那条和货号贴纸；
## 包隔着袋子看得到最上面那条。颜色条是"看得到的颜色"，图案要靠贴纸或翻看。
## 左键点最上面那个 → package_pressed（弹出能做的事）；点空处 → slot_pressed（把手上的放上来）。

signal package_pressed(slot_id: String, at: Vector2)
signal slot_pressed(slot_id: String)

## 一个单位（一包）多高；能放很多的格子（地堆 12 单位）按比例压扁，面板最高约 150
const UNIT_H := 15.0
const MAX_STACK_H := 150.0
const HEAD := 22
const BOX_COLOR := Color("#b08a5a")
const BAG_COLOR := Color(0.85, 0.9, 1.0, 0.25)

var slot: Slot
var title: String = ""
var _hover_top := false
var _unit_h := UNIT_H


func setup(sl: Slot, t: String) -> PackageView:
	slot = sl
	title = t
	var cap := maxi(sl.pkg_capacity, 3)
	_unit_h = clampf(floorf(MAX_STACK_H / cap), 9.0, UNIT_H)
	custom_minimum_size = Vector2(150, HEAD + _unit_h * cap + 10)
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func _rect(i: int) -> Rect2:
	var y := size.y - 6
	for j in i + 1:
		y -= slot.packages[j].units() * _unit_h
	return Rect2(6, y, size.x - 12, slot.packages[i].units() * _unit_h - 2)


func _draw() -> void:
	if slot == null:
		return
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), UIKit.PANEL)
	draw_string(font, Vector2(6, 16), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, 13, UIKit.MUTED)
	var free_units := slot.pkg_capacity - slot.package_units()
	if free_units > 0:
		var top_y := size.y - 6 - slot.package_units() * _unit_h
		draw_rect(Rect2(6, top_y - free_units * _unit_h, size.x - 12, free_units * _unit_h - 2), Color(1, 1, 1, 0.05), false, 1.0)
	var k: Knowledge = Game.state.knowledge if Game.state else null
	for i in slot.packages.size():
		var p: Package = slot.packages[i]
		var r := _rect(i)
		var label: String = k.labels.get(p.id, "") if k else ""
		if p.is_box():
			draw_rect(r, BOX_COLOR if p.sealed else BOX_COLOR.lightened(0.15))
			draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
			if p.sealed:
				draw_rect(Rect2(r.position + Vector2(r.size.x * 0.5 - 6, 0), Vector2(12, r.size.y)), Color(0.85, 0.75, 0.55, 0.8))
			var line1 := "纸箱 %d/%d · %.1fkg%s" % [int(p.waybill.get("piece", 1)), int(p.waybill.get("of", 1)), float(p.waybill.get("weight", 0.0)), "" if p.sealed else " · 已拆"]
			draw_string(font, r.position + Vector2(4, 13), line1, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, 12, Color("#2a2018"))
			if label != "":
				draw_string(font, r.position + Vector2(4, 27), "✎ " + label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, 12, Color("#1a3a8a"))
			elif not p.sealed:
				# 掀开盖：每包最上面那条露出来的颜色
				for j in mini(p.packs.size(), 10):
					var t := p.packs[j].top_item()
					if t != null:
						draw_rect(Rect2(r.position + Vector2(4 + j * 15, 20), Vector2(12, 10)), UIKit.sku_color(t.sku_id))
				draw_string(font, r.position + Vector2(4 + mini(p.packs.size(), 10) * 15 + 4, 29), "%d 包" % p.packs.size(), HORIZONTAL_ALIGNMENT_LEFT, 60, 11, Color("#2a2018"))
		else:
			var t := p.top_item()
			if t != null:
				draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(26, r.size.y - 4)), UIKit.sku_color(t.sku_id))
			draw_rect(r, BAG_COLOR)
			draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)
			var txt := label if label != "" else _sticker_text(p)
			if not p.sealed:
				txt += "（开口 %d 条）" % p.items.size()
			draw_string(font, r.position + Vector2(32, 11), txt, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 11, UIKit.TEXT)
	if _hover_top and not slot.packages.is_empty():
		draw_rect(_rect(slot.packages.size() - 1).grow(1), Color.WHITE, false, 1.5)


## 包上的货号贴纸：款（图案 + 材质），混色包会写"混色"。
static func _sticker_text(p: Package) -> String:
	var a := DataDB.attributes()
	if p.sticker.is_empty():
		return "包"
	return "%s%s%s" % [a["patterns"][p.sticker["pattern"]]["name"], a["materials"][p.sticker["material"]]["name"], "·混色" if p.mix == "mixed" else ""]


func _gui_input(e: InputEvent) -> void:
	if slot == null:
		return
	var on_top := not slot.packages.is_empty() and _rect(slot.packages.size() - 1).has_point(e.position) if e is InputEventMouse else false
	if e is InputEventMouseMotion:
		if on_top != _hover_top:
			_hover_top = on_top
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if on_top:
			package_pressed.emit(slot.id, get_global_mouse_position())
		else:
			slot_pressed.emit(slot.id)
		accept_event()


func refresh() -> void:
	queue_redraw()
