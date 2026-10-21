class_name Iso
extends RefCounted
## 开罗式斜 45° 伪 3D 视角的绘制工具：地面是 2:1 菱形格，物体是带顶面和两个侧面的方块，人物是大头小身的像素小人。
## 世界格坐标 (gx, gy)：gx 沿街（屏幕右下方向），gy 横穿街（屏幕左下方向）。
## 调用方在自己的 _draw 里用；需要缩放时先 draw_set_transform。远处的先画，按 depth() 排序。
##
## 像素风：所有精灵都按 PX 倍放大画（1 个美术像素 = PX 个屏幕像素），位置用 snap() 对齐到像素网格，
## 外层 draw_set_transform 的缩放请用 0.5 的整数倍，这样像素才不会忽大忽小。
## 精灵由 tools/pixelart/gen_sprites.py 生成到 assets/sprites/（标清）和 assets/sprites_hd/（高清，两倍精细），
## 人物是分层灰度图，按颜色 modulate 上色换装。档位见 set_tier。

const TW := 64.0
const TH := 32.0
## 一个美术像素占几个屏幕像素
const PX := 2.0
const SKIN := Color("#f0d2b0")
const OUTLINE := Color(0.08, 0.07, 0.1, 0.55)

## 人物一帧的美术像素尺寸、脚底在帧里的高度、帧数、发型数（和生成脚本一致）
const FW := 24
const FH := 32
const FOOT_Y := 30
const FRAMES := 4
const HAIR_STYLES := 7
## 发型序号：短发、偏分、波波头、长发、马尾、发髻、鸭舌帽
enum Hair { SHORT, PARTED, BOB, LONG, PONYTAIL, BUN, CAP }

## 资源档位：sd 标清（1 美术像素 = 2 屏幕像素）/ hd 高清（两倍精细，1 美术像素 = 1 屏幕像素）。
## 坐标、尺寸、元数据全按标清单位写，S 是当前档位每个标清单位对应的美术像素数，取图时乘上去。
static var tier := "sd"
static var S := 1
static var _tex_cache: Dictionary = {}


## "sd" / "hd" / "auto"：auto 按窗口高度选，1440p 及以上用高清（这时一个标清单位 ≥ 2 个物理像素，高清图才有地方发挥）。
static func set_tier(t: String) -> void:
	if t == "auto":
		var h := 720
		if DisplayServer.get_name() != "headless":
			h = DisplayServer.window_get_size().y
		t = "hd" if h >= 1300 else "sd"
	if t != "hd":
		t = "sd"
	tier = t
	S = 2 if t == "hd" else 1
	_tex_cache.clear()


static func sprite_tex(name: String) -> Texture2D:
	var key := tier + "/" + name
	if not _tex_cache.has(key):
		_tex_cache[key] = load("res://assets/%s/%s.png" % ["sprites_hd" if tier == "hd" else "sprites", name])
	return _tex_cache[key]


static func to_screen(g: Vector2, origin: Vector2) -> Vector2:
	return origin + Vector2((g.x - g.y) * TW * 0.5, (g.x + g.y) * TH * 0.5)


## 画家算法的排序键：越靠近屏幕下方越晚画。
static func depth(g: Vector2) -> float:
	return g.x + g.y


## 对齐到像素网格。
static func snap(p: Vector2) -> Vector2:
	return (p / PX).floor() * PX


static func tile_points(g: Vector2, origin: Vector2, w := 1.0, d := 1.0) -> PackedVector2Array:
	return PackedVector2Array([
		to_screen(g, origin), to_screen(g + Vector2(w, 0), origin),
		to_screen(g + Vector2(w, d), origin), to_screen(g + Vector2(0, d), origin),
	])


## 纯色菱形（高亮、范围提示用）。地面请用 draw_ground。
static func draw_tile(ci: CanvasItem, origin: Vector2, g: Vector2, col: Color, w := 1.0, d := 1.0, outline := Color(0, 0, 0, 0.12)) -> void:
	var pts := tile_points(g, origin, w, d)
	ci.draw_colored_polygon(pts, col)
	if outline.a > 0.0:
		pts.append(pts[0])
		ci.draw_polyline(pts, outline, PX)


## 一格地面贴图。kind：pavement 人行道 / road 街面 / grass 花坛 / lot 空地；variant 换一张花色。
## kerb 为 "nw" / "se" 时在这格靠那条边上叠一道路缘石（人行道挨着街的那条边）。
static func draw_ground(ci: CanvasItem, origin: Vector2, g: Vector2, kind: String, variant := 0, kerb := "") -> void:
	if not kind in ["pavement", "road", "grass", "lot"]:
		kind = "pavement"
	var tex := sprite_tex("tile_%s_%d" % [kind, absi(variant) % 2])
	var p := snap(to_screen(g, origin) - Vector2(TW * 0.5, 0))
	ci.draw_texture_rect(tex, Rect2(p, Vector2(TW, TH)), false)
	if kerb == "nw" or kerb == "se":
		ci.draw_texture_rect(sprite_tex("kerb_" + kerb), Rect2(p, Vector2(TW, TH)), false)


## 方块：占地 w×d 格，高 h 像素。顶面亮、朝左前的面原色、朝右前的面暗，看起来有体积。
static func draw_box(ci: CanvasItem, origin: Vector2, g: Vector2, w: float, d: float, h: float, col: Color, top: Color = Color(0, 0, 0, 0)) -> void:
	var up := Vector2(0, -snappedf(h, PX))
	var b := snap(to_screen(g + Vector2(w, 0), origin))
	var c := snap(to_screen(g + Vector2(w, d), origin))
	var dd := snap(to_screen(g + Vector2(0, d), origin))
	var a := snap(to_screen(g, origin))
	var left := PackedVector2Array([dd, c, c + up, dd + up])
	var right := PackedVector2Array([c, b, b + up, c + up])
	ci.draw_colored_polygon(left, col)
	ci.draw_colored_polygon(right, col.darkened(0.28))
	var tp := PackedVector2Array([a + up, b + up, c + up, dd + up])
	ci.draw_colored_polygon(tp, top if top.a > 0.0 else col.lightened(0.18))
	tp.append(tp[0])
	ci.draw_polyline(tp, OUTLINE, PX)
	ci.draw_line(c, c + up, OUTLINE, PX)


## 朝左前的面上画一块贴面（窗、门、招牌）：u 沿面横向 0–1，v 从地面往上的像素。
static func draw_face_rect(ci: CanvasItem, origin: Vector2, g: Vector2, w: float, d: float, u0: float, u1: float, v0: float, v1: float, col: Color) -> void:
	var a := snap(to_screen(g + Vector2(w * u0, d), origin))
	var b := snap(to_screen(g + Vector2(w * u1, d), origin))
	v0 = snappedf(v0, PX)
	v1 = snappedf(v1, PX)
	ci.draw_colored_polygon(PackedVector2Array([a - Vector2(0, v0), b - Vector2(0, v0), b - Vector2(0, v1), a - Vector2(0, v1)]), col)


static func draw_shadow(ci: CanvasItem, foot: Vector2, rx: float, ry: float, a := 0.3) -> void:
	var size := snap(Vector2(maxf(rx * 2.0, PX * 2), maxf(ry * 2.0, PX)))
	ci.draw_texture_rect(sprite_tex("shadow"), Rect2(snap(foot - size * 0.5), size), false, Color(1, 1, 1, a))


## 摊桌：四条腿的木板桌，铺一块桌布垂到两面。占地 w×d 格，桌面高 h 像素。
static func draw_stall_table(ci: CanvasItem, origin: Vector2, g: Vector2, w: float, d: float, h: float, wood := Color("#7a5a3a"), cloth := Color("#9c3c3c")) -> void:
	h = snappedf(h, PX)
	var leg := wood.darkened(0.4)
	for corner in [g + Vector2(0.08, d - 0.1), g + Vector2(w - 0.08, d - 0.1), g + Vector2(w - 0.08, 0.1), g + Vector2(0.08, 0.1)]:
		var p := snap(to_screen(corner, origin))
		ci.draw_rect(Rect2(p - Vector2(PX, h), Vector2(PX * 2, h)), leg)
	draw_box(ci, origin, g, w, d, h, wood, wood.lightened(0.25))
	# 桌布：盖住桌面，顺着两个朝镜头的面垂下一截，下摆一格一格的褶
	var up := Vector2(0, -h)
	var a := snap(to_screen(g, origin)) + up
	var b := snap(to_screen(g + Vector2(w, 0), origin)) + up
	var c := snap(to_screen(g + Vector2(w, d), origin)) + up
	var dd := snap(to_screen(g + Vector2(0, d), origin)) + up
	ci.draw_colored_polygon(PackedVector2Array([a, b, c, dd]), cloth.lightened(0.12))
	var drop := Vector2(0, snappedf(minf(h * 0.45, 8.0), PX))
	ci.draw_colored_polygon(PackedVector2Array([dd, c, c + drop, dd + drop]), cloth)
	ci.draw_colored_polygon(PackedVector2Array([c, b, b + drop, c + drop]), cloth.darkened(0.3))
	var hem := cloth.darkened(0.45)
	var n := int((c - dd).length() / (PX * 4))
	for i in range(0, n, 2):
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		ci.draw_colored_polygon(PackedVector2Array([dd.lerp(c, t0) + drop, dd.lerp(c, t1) + drop, dd.lerp(c, t1) + drop + Vector2(0, PX), dd.lerp(c, t0) + drop + Vector2(0, PX)]), hem)
	n = int((b - c).length() / (PX * 4))
	for i in range(1, n, 2):
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		ci.draw_colored_polygon(PackedVector2Array([c.lerp(b, t0) + drop, c.lerp(b, t1) + drop, c.lerp(b, t1) + drop + Vector2(0, PX), c.lerp(b, t0) + drop + Vector2(0, PX)]), hem)
	ci.draw_polyline(PackedVector2Array([a, b, c, dd, a]), OUTLINE, PX)


## 叠好的一份围巾（侧面能看到颜色）：bottom 是这份货的底边中点。一叠往上摞时每层高 FOLD_STEP。
const FOLD_STEP := 2.0 * PX
static func draw_scarf_fold(ci: CanvasItem, bottom: Vector2, col: Color, jitter := 0) -> void:
	var tex := sprite_tex("scarf_fold")
	var size := Vector2(tex.get_width(), tex.get_height()) / S * PX
	var p := snap(bottom - Vector2(size.x * 0.5, size.y)) + Vector2(float(jitter % 3 - 1) * PX, 0)
	ci.draw_texture_rect(tex, Rect2(p, size), false, col)


## 客人头顶的气泡：kind = ask 问价 / haggle 讲价 / wait 等货。pos 是气泡左上角。
static func draw_bubble(ci: CanvasItem, pos: Vector2, kind: String, a := 1.0) -> void:
	if not kind in ["ask", "haggle", "wait"]:
		return
	var tex := sprite_tex("bubble_" + kind)
	ci.draw_texture_rect(tex, Rect2(snap(pos), Vector2(tex.get_width(), tex.get_height()) / S * PX), false, Color(1, 1, 1, a))


## 大头小身的像素小人，脚底在 foot。facing：+1 朝右前，-1 朝左前；back=true 背对镜头（看不到脸）。
## phase 为走路动画相位（秒），站着传 0。k 放大倍数只取整（1 或 2），像素才整齐。
## style 发型（Hair 枚举，-1 按衣服发色自动挑一个）；pants 裤色（透明 = 按上衣加深）；scarf 有颜色就围一条围巾。
## 颜色的 alpha 会一起作用到整个人（路人淡出用）。
static func draw_person(ci: CanvasItem, foot: Vector2, body: Color, hair: Color, facing := 1.0, phase := 0.0, back := false, k := 1.0, style := -1, pants := Color(0, 0, 0, 0), scarf := Color(0, 0, 0, 0)) -> void:
	var px := PX * maxf(1.0, floorf(k))
	var a := body.a
	draw_shadow(ci, foot, 8.0 * px, 3.0 * px, 0.3 * a)
	var dir := (2 if back else 0) + (1 if facing < 0.0 else 0)
	var frame := 0 if phase == 0.0 else int(floor(phase * 6.4)) % FRAMES
	if style < 0:
		style = absi(body.to_rgba32() ^ hair.to_rgba32()) % HAIR_STYLES
	style = clampi(style, 0, HAIR_STYLES - 1)
	var size := Vector2(FW, FH) * px
	var pos := snap(foot - Vector2(FW * 0.5, FOOT_Y) * px)
	var dst := Rect2(pos, size)
	var src := Rect2(Vector2(frame * FW, dir * FH) * S, Vector2(FW, FH) * S)
	var hsrc := Rect2(Vector2(frame * FW, (style * 4 + dir) * FH) * S, Vector2(FW, FH) * S)
	var white := Color(1, 1, 1, a)
	if pants.a <= 0.0:
		pants = body.darkened(0.45)
		pants.a = a
	var skin := SKIN
	skin.a = a
	hair.a = a
	ci.draw_texture_rect_region(sprite_tex("person_outline"), dst, hsrc, white)
	ci.draw_texture_rect_region(sprite_tex("person_skin"), dst, src, skin)
	ci.draw_texture_rect_region(sprite_tex("person_top"), dst, src, body)
	ci.draw_texture_rect_region(sprite_tex("person_bottom"), dst, src, pants)
	ci.draw_texture_rect_region(sprite_tex("person_shoes"), dst, src, white)
	ci.draw_texture_rect_region(sprite_tex("hair"), dst, hsrc, hair)
	ci.draw_texture_rect_region(sprite_tex("person_face"), dst, src, white)
	if scarf.a > 0.0:
		scarf.a *= a
		ci.draw_texture_rect_region(sprite_tex("person_scarf"), dst, src, scarf)


## 人物在屏幕上占的范围（点击判定用）：脚底在 foot。
static func person_rect(foot: Vector2, k := 1.0) -> Rect2:
	var px := PX * maxf(1.0, floorf(k))
	return Rect2(foot + Vector2(-FW * 0.5, -FOOT_Y) * px, Vector2(FW, FOOT_Y + 1) * px)


## 格坐标里的移动 / 朝向方向 → draw_person 用的 [facing, back]。
## 四个朝向：+gx 右前（脸朝镜头）、+gy 左前（脸朝镜头）、-gx 左后（背对）、-gy 右后（背对）。
static func facing_of(dir: Vector2) -> Array:
	var sx := dir.x - dir.y
	var sy := dir.x + dir.y
	return [1.0 if sx >= 0.0 else -1.0, sy < 0.0]


## 按 id 稳定地给路人挑一套衣服 / 发色（旧接口，返回 [上衣, 发色]）。
static func outfit(seed_value: int) -> Array:
	var o := outfit_full(seed_value)
	return [o["top"], o["hair"]]


## 按 id 稳定地挑一整套打扮：{top 上衣, pants 裤子, hair 发色, style 发型, scarf 围巾颜色（多数人是透明）}。
static func outfit_full(seed_value: int) -> Dictionary:
	const TOPS := ["#c85a3c", "#3c7ac8", "#5aa05a", "#9a5ac8", "#d8a03c", "#4a8a8a", "#c8c0b0", "#6a6a7a", "#b84a7a", "#e0e0e0", "#2e4a7a", "#8a6a4a"]
	const PANTS := ["#3a3a4a", "#5a4a3a", "#2a3a5a", "#6a6a6a", "#2a2a2a", "#7a7060"]
	const HAIRS := ["#2a2026", "#4a3020", "#6a4a2a", "#1a1a1a", "#8a6a4a", "#b0a090", "#3a2a2a"]
	const SCARVES := ["#c0392b", "#22315a", "#e6d5b8", "#7d3c98", "#1e5631", "#b5835a"]
	var s := absi(seed_value)
	var scarf := Color(0, 0, 0, 0)
	if (s / 97) % 4 == 0:
		scarf = Color(SCARVES[(s / 389) % SCARVES.size()])
	return {
		"top": Color(TOPS[s % TOPS.size()]),
		"pants": Color(PANTS[(s / 13) % PANTS.size()]),
		"hair": Color(HAIRS[(s / 7) % HAIRS.size()]),
		"style": (s / 31) % HAIR_STYLES,
		"scarf": scarf,
	}


# ---------------------------------------------------------------- 设备（店面 / 仓库，01 §4.9）
## 设备精灵由 tools/pixelart/gen_equipment.py 生成，元数据在 assets/sprites/equipment.json：
## size 图的美术像素尺寸、anchor 地面菱形最上角在图里的位置、H 高度（美术像素）、tiers 每层层板高度、slot 放货的格内偏移。

static var _equip_meta: Dictionary = {}


static func sprite_meta(name: String) -> Dictionary:
	if _equip_meta.is_empty():
		var f := FileAccess.open("res://assets/sprites/equipment.json", FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_equip_meta = parsed
	return _equip_meta.get(name, {})


## 画一张带锚点的精灵：地面菱形最上角对到格坐标 g，再往上抬 up 个美术像素（放在层板上用）。
static func draw_sprite(ci: CanvasItem, origin: Vector2, g: Vector2, name: String, col := Color.WHITE, up := 0.0) -> void:
	var m := sprite_meta(name)
	var tex := sprite_tex(name)
	if m.is_empty() or tex == null:
		return
	var anchor := Vector2(m["anchor"][0], m["anchor"][1])
	var size := Vector2(m["size"][0], m["size"][1])
	var p := snap(to_screen(g, origin)) - (anchor + Vector2(0, up)) * PX
	ci.draw_texture_rect(tex, Rect2(p, size * PX), false, col)


## 设备的高度（屏幕像素，和 draw_box 的 h 一个单位），排序 / 遮挡用。
static func equipment_height(kind: String, facing := "sw") -> float:
	var m := sprite_meta(_equip_name(kind, facing))
	return float(m.get("H", 0)) * PX


static func _equip_name(kind: String, facing: String) -> String:
	if kind in ["mannequin", "carton", "bag"]:
		return "eq_" + kind
	return "eq_%s_%s" % [kind, facing]


## 画一件设备，占地 1×1 格（手推车 0.9×0.7），g 是它占的那格。
## kind：shop_shelf 货架 / shop_cabinet 货柜 / shop_window 橱窗 / mannequin 模特 / shop_counter 收银台 /
##       warehouse_rack 仓库货架 / carton 纸箱 / bag 整包 / handcart 手推车
## facing：开口朝 "sw"（左前）还是 "se"（右前）。
## extra：tiers = [[每层从下往上各份围巾的颜色], ...]（货架、橱窗）；scarf = 模特身上围巾的颜色；
##        boxes / bags = [每层的箱数 / 包数]（仓库货架，每层 2 箱或 6 包）；count = 地堆纸箱摞几个。
static func draw_equipment(ci: CanvasItem, origin: Vector2, g: Vector2, kind: String, facing := "sw", extra := {}) -> void:
	var name := _equip_name(kind, facing)
	var m := sprite_meta(name)
	if m.is_empty():
		return
	if kind == "carton":
		for i in maxi(1, int(extra.get("count", 1))):
			draw_sprite(ci, origin, g, name, Color.WHITE, i * float(m["H"]))
		return
	draw_sprite(ci, origin, g, name, extra.get("col", Color.WHITE))
	var tiers: Array = m.get("tiers", [])
	var slot := Vector2(m["slot"][0], m["slot"][1]) if m.has("slot") else Vector2(0.5, 0.5)
	if extra.has("tiers"):
		var fold := "fold_" + facing
		var fh := float(sprite_meta(fold).get("H", 3))
		for k in mini(tiers.size(), extra["tiers"].size()):
			var i := 0
			for c in extra["tiers"][k]:
				draw_sprite(ci, origin, g + slot, fold, c, float(tiers[k]) + i * fh)
				i += 1
	if extra.has("boxes"):
		for k in mini(tiers.size(), extra["boxes"].size()):
			for i in int(extra["boxes"][k]):
				var off := Vector2(0.5 * i, 0) if facing == "sw" else Vector2(0, 0.5 * i)
				draw_sprite(ci, origin, g + slot + off, "eq_carton_small_" + facing, Color.WHITE, float(tiers[k]))
	if extra.has("bags"):
		for k in mini(tiers.size(), extra["bags"].size()):
			for i in int(extra["bags"][k]):
				var a := i % 3
				var b := i / 3
				var off := Vector2(0.3 * a, 0.45 * b) if facing == "sw" else Vector2(0.45 * b, 0.3 * a)
				draw_sprite(ci, origin, g + slot + off, "eq_bag", Color.WHITE, float(tiers[k]))
	if kind == "shop_window":
		draw_sprite(ci, origin, g, "eq_shop_window_glass_" + facing)
	if kind == "mannequin" and extra.has("scarf"):
		draw_sprite(ci, origin, g, "eq_mannequin_scarf", extra["scarf"])
