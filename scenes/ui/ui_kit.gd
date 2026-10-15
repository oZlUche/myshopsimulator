class_name UIKit
extends RefCounted
## 占位 UI 的小工具（阶段 0 不做美术，统一深色风格）。

const BG := Color("#1d1f2b")
const PANEL := Color("#2a2d3e")
const TEXT := Color("#e8e6df")
const MUTED := Color("#9a98a6")
const ACCENT := Color("#f2b134")
const GOOD := Color("#6cc070")
const BAD := Color("#e05a4f")


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	return b


static func panel(color: Color = PANEL, pad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	parent.move_child(bg, 0)


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## SKU 的外观名（颜色 + 图案 + 材质），进货时看得到的信息。
static func sku_name(sku_id: String) -> String:
	return DataDB.sku_display_name(sku_id)


static func sku_color(sku_id: String) -> Color:
	var s := DataDB.sku(sku_id)
	if s.is_empty():
		return Color.GRAY
	return Color(DataDB.attributes()["colors"][s["color"]]["rgb"])


## 单场景 tscn 只有一个根节点挂脚本，界面都在代码里搭。
static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c
