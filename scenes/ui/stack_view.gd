class_name StackView
extends Control
## 画一个槽位的货堆（03 文档）：从正面只看得到每份货的边缘条（颜色），图案要翻看才知道。
## 点堆顶那份的顶面（或最上面那份）= 从顶部拿一份；点下面某份的侧面边缘条 = 抽取；
## 右键 = 翻看；点空处 = 把手上的货放到这一堆顶上；点地上那堆 = 拾起（03 §2.0）。
## 只读认知层：翻看结果、强化记忆悬浮框；颜色条是"露在外面能看到的颜色"。

signal top_pressed(slot_id: String)
signal strip_pressed(slot_id: String, index: int)
signal strip_peek(slot_id: String, index: int)
signal slot_pressed(slot_id: String)
signal pile_pressed(slot_id: String)

const STRIP_H := 14
const PILE_H := 22
## 堆顶那份露出的顶面（点这里 = 从顶部拿）
const TOP_H := 6
## 抽出 / 带歪的位移在小格子里按比例缩小画，免得画出格子
const SHOW_SCALE := 0.3

var slot: Slot
var title: String = ""
var selected_index: int = -1
## 高亮某份货（例如客人指着的那份）
var highlight_item_id: String = ""
var _hover_index := -1
var _hover_top := false


func setup(sl: Slot, t: String) -> StackView:
	slot = sl
	title = t
	custom_minimum_size = Vector2(120, 26 + TOP_H + STRIP_H * sl.stack.max_height + PILE_H + 8)
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func _strip_rect(i: int) -> Rect2:
	var bottom := size.y - PILE_H - 6
	var off := 6.0 if slot.stack.displaced and i > 0 else 0.0
	return Rect2(8 + off * (i % 2), bottom - (i + 1) * STRIP_H, size.x - 16 - off, STRIP_H - 2)


## 实际摆放位置：抽到一半的货露在外面，被带歪的货偏在一边，下面被抽空的层留着空隙（03 §2.1、§2.4）。
func _item_rect(i: int) -> Rect2:
	var r := _strip_rect(slot.stack.layer_of(i))
	var it: ScarfItem = slot.stack.items[i]
	return Rect2(r.position + Vector2((it.pull_out + it.shift) * r.size.x * SHOW_SCALE, 0), r.size)


## 堆顶那份的顶面：画成它上方一条浅色的斜面。
func _top_rect() -> Rect2:
	if slot.stack.height() == 0:
		return Rect2()
	var r := _item_rect(slot.stack.height() - 1)
	return Rect2(r.position + Vector2(3, -TOP_H), Vector2(r.size.x - 6, TOP_H))


func _pile_rect() -> Rect2:
	return Rect2(4, size.y - PILE_H - 2, size.x - 8, PILE_H)


func _draw() -> void:
	if slot == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), UIKit.PANEL)
	draw_string(get_theme_default_font(), Vector2(6, 16), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, 13, UIKit.MUTED)
	# 空位轮廓
	for i in slot.stack.max_height:
		var r := _strip_rect(i)
		draw_rect(r, Color(1, 1, 1, 0.06), false, 1.0)
	var k: Knowledge = Game.state.knowledge if Game.state else null
	for i in slot.stack.height():
		var it: ScarfItem = slot.stack.items[i]
		var r := _item_rect(i)
		draw_rect(r, UIKit.sku_color(it.sku_id))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.18))
		draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
		if k and k.perceived.has(it.id):
			var guess: String = k.perceived[it.id]["sku_guess"]
			var pat: String = DataDB.attributes()["patterns"][DataDB.sku(guess)["pattern"]]["name"]
			var mark := pat + ("?" if k.perceived[it.id]["may_be_wrong"] else "")
			draw_string(get_theme_default_font(), r.position + Vector2(4, 11), mark, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, 11, _ink(UIKit.sku_color(it.sku_id)))
		if i == selected_index:
			draw_rect(r.grow(1), UIKit.ACCENT, false, 2.0)
		elif it.id == highlight_item_id:
			draw_rect(r.grow(1), Color.WHITE, false, 2.0)
		elif i == _hover_index:
			draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)
	if slot.stack.height() > 0:
		var top := slot.stack.items[-1]
		var tr := _top_rect()
		var face := UIKit.sku_color(top.sku_id).lightened(0.35)
		draw_colored_polygon(PackedVector2Array([tr.position + Vector2(0, tr.size.y), tr.position + Vector2(4, 0),
			tr.end - Vector2(4, tr.size.y), tr.end]), face)
		if _hover_top:
			draw_rect(tr.grow(1), Color.WHITE, false, 1.0)
	var pile := slot.stack.collapsed_pile.size()
	if pile > 0:
		var pr := _pile_rect()
		for j in mini(pile, 8):
			var it: ScarfItem = slot.stack.collapsed_pile[j]
			var rr := Rect2(pr.position + Vector2(6 + j * 11, 4 + (j % 3) * 4), Vector2(18, 8))
			draw_rect(rr, UIKit.sku_color(it.sku_id))
		draw_string(get_theme_default_font(), pr.position + Vector2(pr.size.x - 70, 16), "地上 %d 份" % pile, HORIZONTAL_ALIGNMENT_RIGHT, 66, 12, UIKit.BAD)


func _ink(bg: Color) -> Color:
	return Color.BLACK if bg.get_luminance() > 0.55 else Color.WHITE


func _index_at(p: Vector2) -> int:
	for i in slot.stack.height():
		if _item_rect(i).has_point(p):
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if slot == null:
		return
	if e is InputEventMouseMotion:
		var h := _index_at(e.position)
		var ht := _top_rect().grow(1).has_point(e.position)
		if h != _hover_index or ht != _hover_top:
			_hover_index = h
			_hover_top = ht
			_update_tooltip()
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		var i := _index_at(e.position)
		var on_top := _top_rect().grow(1).has_point(e.position)
		if _pile_rect().has_point(e.position) and not slot.stack.collapsed_pile.is_empty():
			pile_pressed.emit(slot.id)
		elif i >= 0 and e.button_index == MOUSE_BUTTON_RIGHT:
			strip_peek.emit(slot.id, i)
		elif e.button_index == MOUSE_BUTTON_LEFT and (on_top or (i >= 0 and i == slot.stack.height() - 1)):
			# 堆顶那份：点顶面和点侧面一样，直接拿
			top_pressed.emit(slot.id)
		elif i >= 0 and e.button_index == MOUSE_BUTTON_LEFT:
			strip_pressed.emit(slot.id, i)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			slot_pressed.emit(slot.id)
		accept_event()


## 强化记忆悬浮框：有记忆的槽位直接显示文本，无需翻看、不会认错（02 §2.2）。
func _update_tooltip() -> void:
	if Game.state == null:
		return
	var mem := Sampler.memory_tooltip(Game.state.knowledge, slot.id, Game.state.player)
	var lines: Array = []
	if mem != "":
		lines.append("记忆：" + mem)
	var label: String = Game.state.knowledge.labels.get(slot.id, "")
	if label != "":
		lines.append("标签：" + label)
	lines.append("点顶面：从顶部拿一份（不会塌） / 点侧面：从中间抽 / 右键翻看 / 点空处：把手上的货放到堆顶")
	tooltip_text = "\n".join(lines)


func refresh() -> void:
	_update_tooltip()
	queue_redraw()
