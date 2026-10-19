class_name Iso
extends RefCounted
## 开罗式斜 45° 伪 3D 视角的绘制工具：地面是 2:1 菱形格，物体是带顶面和两个侧面的方块，人物是大头小身的伪 3D 小人。
## 世界格坐标 (gx, gy)：gx 沿街（屏幕右下方向），gy 横穿街（屏幕左下方向）。
## 调用方在自己的 _draw 里用；需要缩放时先 draw_set_transform。远处的先画，按 depth() 排序。

const TW := 64.0
const TH := 32.0
const SKIN := Color("#f0d2b0")
const OUTLINE := Color(0.08, 0.07, 0.1, 0.55)


static func to_screen(g: Vector2, origin: Vector2) -> Vector2:
	return origin + Vector2((g.x - g.y) * TW * 0.5, (g.x + g.y) * TH * 0.5)


## 画家算法的排序键：越靠近屏幕下方越晚画。
static func depth(g: Vector2) -> float:
	return g.x + g.y


static func tile_points(g: Vector2, origin: Vector2, w := 1.0, d := 1.0) -> PackedVector2Array:
	return PackedVector2Array([
		to_screen(g, origin), to_screen(g + Vector2(w, 0), origin),
		to_screen(g + Vector2(w, d), origin), to_screen(g + Vector2(0, d), origin),
	])


static func draw_tile(ci: CanvasItem, origin: Vector2, g: Vector2, col: Color, w := 1.0, d := 1.0, outline := Color(0, 0, 0, 0.12)) -> void:
	var pts := tile_points(g, origin, w, d)
	ci.draw_colored_polygon(pts, col)
	if outline.a > 0.0:
		pts.append(pts[0])
		ci.draw_polyline(pts, outline, 1.0)


## 方块：占地 w×d 格，高 h 像素。顶面亮、朝左前的面原色、朝右前的面暗，看起来有体积。
static func draw_box(ci: CanvasItem, origin: Vector2, g: Vector2, w: float, d: float, h: float, col: Color, top: Color = Color(0, 0, 0, 0)) -> void:
	var up := Vector2(0, -h)
	var b := to_screen(g + Vector2(w, 0), origin)
	var c := to_screen(g + Vector2(w, d), origin)
	var dd := to_screen(g + Vector2(0, d), origin)
	var left := PackedVector2Array([dd, c, c + up, dd + up])
	var right := PackedVector2Array([c, b, b + up, c + up])
	ci.draw_colored_polygon(left, col)
	ci.draw_colored_polygon(right, col.darkened(0.28))
	var tp := tile_points(g, origin + up, w, d)
	ci.draw_colored_polygon(tp, top if top.a > 0.0 else col.lightened(0.18))
	tp.append(tp[0])
	ci.draw_polyline(tp, OUTLINE, 1.0)
	ci.draw_line(c, c + up, OUTLINE, 1.0)


## 朝左前的面上画一块贴面（窗、门、招牌）：u 沿面横向 0–1，v 从地面往上的像素。
static func draw_face_rect(ci: CanvasItem, origin: Vector2, g: Vector2, w: float, d: float, u0: float, u1: float, v0: float, v1: float, col: Color) -> void:
	var a := to_screen(g + Vector2(w * u0, d), origin)
	var b := to_screen(g + Vector2(w * u1, d), origin)
	ci.draw_colored_polygon(PackedVector2Array([a - Vector2(0, v0), b - Vector2(0, v0), b - Vector2(0, v1), a - Vector2(0, v1)]), col)


static func draw_shadow(ci: CanvasItem, foot: Vector2, rx: float, ry: float, a := 0.3) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var t := TAU * i / 16.0
		pts.append(foot + Vector2(cos(t) * rx, sin(t) * ry))
	ci.draw_colored_polygon(pts, Color(0, 0, 0, a))


## 大头小身的伪 3D 小人，脚底在 foot。facing：+1 朝右前，-1 朝左前；back=true 背对镜头（看不到脸）。
## phase 为走路动画相位（秒），站着传 0。
static func draw_person(ci: CanvasItem, foot: Vector2, body: Color, hair: Color, facing := 1.0, phase := 0.0, back := false, k := 1.0) -> void:
	draw_shadow(ci, foot, 9.0 * k, 4.0 * k)
	var swing := sin(phase * 10.0) * 2.0 * k if phase != 0.0 else 0.0
	var pants := body.darkened(0.45)
	# 腿
	ci.draw_rect(Rect2(foot + Vector2(-4.5 * k, -7 * k + swing * 0.5), Vector2(3.5 * k, 7 * k - swing * 0.5)), pants)
	ci.draw_rect(Rect2(foot + Vector2(1.0 * k, -7 * k - swing * 0.5), Vector2(3.5 * k, 7 * k + swing * 0.5)), pants.darkened(0.15))
	# 身体：正面 + 一条侧面，侧面在背光那边
	var torso := Rect2(foot + Vector2(-6 * k, -17 * k), Vector2(12 * k, 11 * k))
	ci.draw_rect(torso, body)
	var side_w := 3.0 * k
	var side_x := torso.position.x if facing > 0.0 else torso.end.x - side_w
	ci.draw_rect(Rect2(Vector2(side_x, torso.position.y), Vector2(side_w, torso.size.y)), body.darkened(0.25))
	ci.draw_rect(torso, OUTLINE, false, 1.0)
	# 手臂随步伐前后摆
	ci.draw_rect(Rect2(foot + Vector2(-8 * k, -16 * k - swing), Vector2(2.5 * k, 8 * k)), body.darkened(0.12))
	ci.draw_rect(Rect2(foot + Vector2(5.5 * k, -16 * k + swing), Vector2(2.5 * k, 8 * k)), body.darkened(0.12))
	# 大头
	var head := foot + Vector2(0, -25 * k)
	var r := 8.0 * k
	ci.draw_circle(head, r, SKIN)
	ci.draw_circle(head + Vector2(-facing * 2.5 * k, 0), r * 0.92, SKIN.darkened(0.06))
	ci.draw_circle(head + Vector2(facing * 1.0 * k, 0), r * 0.85, SKIN)
	if back:
		ci.draw_circle(head, r, hair)
	else:
		# 头发盖住上半和背后那侧
		var cap := PackedVector2Array()
		for i in 13:
			var t := PI + 0.1 + (PI - 0.2) * i / 12.0
			cap.append(head + Vector2(cos(t) * r * 1.05, sin(t) * r * 1.05))
		ci.draw_colored_polygon(cap, hair)
		ci.draw_circle(head + Vector2(-facing * r * 0.7, -r * 0.1), r * 0.45, hair)
		# 眼睛偏向朝向那一侧
		var eye := head + Vector2(facing * 2.5 * k, 1.5 * k)
		ci.draw_rect(Rect2(eye + Vector2(-3.2 * k, 0), Vector2(1.6 * k, 2.4 * k)), Color("#2a2230"))
		ci.draw_rect(Rect2(eye + Vector2(1.6 * k, 0), Vector2(1.6 * k, 2.4 * k)), Color("#2a2230"))
	ci.draw_arc(head, r, 0.0, TAU, 20, OUTLINE, 1.0)


## 按 id 稳定地给路人挑一套衣服 / 发色。
static func outfit(seed_value: int) -> Array:
	const BODIES := ["#c85a3c", "#3c7ac8", "#5aa05a", "#9a5ac8", "#d8a03c", "#4a8a8a", "#c8c0b0", "#6a6a7a", "#b84a7a"]
	const HAIRS := ["#2a2026", "#4a3020", "#6a4a2a", "#1a1a1a", "#8a6a4a", "#b0a090"]
	return [Color(BODIES[absi(seed_value) % BODIES.size()]), Color(HAIRS[(absi(seed_value) / 7) % HAIRS.size()])]
