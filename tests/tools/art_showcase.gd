extends SceneTree
## 美术陈列室：把每种地面、人物朝向 / 帧 / 发型、设备（带货）各画一遍。
## CI 里无界面运行，只为了让 Iso 的每个绘制函数都跑一次、不报脚本错误；本地有显示时设 SHOTS=目录 可以截图看效果：
##   SHOTS=/tmp/shots xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/tools/art_showcase.gd


class Showcase extends Control:
	var drawn := false

	func _draw() -> void:
		drawn = true
		draw_rect(Rect2(Vector2.ZERO, size), Color("#14151d"))
		var o := Vector2(600, 150)
		const COLS := 12
		const ROWS := 9
		for gx in COLS:
			for gy in ROWS:
				var kind := "pavement"
				var kerb := ""
				if gy == 0:
					kind = "road"
				elif gy == 1:
					kerb = "nw"
				elif gy >= 7:
					kind = "grass" if gx < 6 else "lot"
				Iso.draw_ground(self, o, Vector2(gx, gy), kind, gx * 7 + gy * 13, kerb)
		var red := Color("#c0392b")
		var navy := Color("#22315a")
		var beige := Color("#e6d5b8")
		var purple := Color("#7d3c98")
		var green := Color("#1e5631")
		var camel := Color("#b5835a")
		# 后排：店面设备（开口朝 SW），再往右是仓库设备
		var things: Array = []
		things.append({"g": Vector2(0, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(0, 1), "shop_shelf", "sw", {"tiers": [[red, red, navy], [beige, purple], [green, green, camel]]})})
		things.append({"g": Vector2(1, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(1, 1), "shop_cabinet", "sw")})
		things.append({"g": Vector2(2, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(2, 1), "shop_window", "sw", {"tiers": [[red, navy], [purple]]})})
		things.append({"g": Vector2(3, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(3, 1), "mannequin", "sw", {"scarf": red})})
		things.append({"g": Vector2(4, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(4, 1), "shop_counter", "sw")})
		things.append({"g": Vector2(6, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(6, 1), "warehouse_rack", "sw", {"boxes": [2, 1, 0]})})
		things.append({"g": Vector2(7, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(7, 1), "warehouse_rack", "sw", {"bags": [6, 3, 1]})})
		things.append({"g": Vector2(9, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(9, 1), "carton", "sw", {"count": 4})})
		things.append({"g": Vector2(10, 1), "f": func(): Iso.draw_equipment(self, o, Vector2(10, 1), "carton", "sw", {"count": 2})})
		# 左列：同样的设备开口朝 SE
		things.append({"g": Vector2(0, 3), "f": func(): Iso.draw_equipment(self, o, Vector2(0, 3), "shop_shelf", "se", {"tiers": [[red], [navy, navy], [camel]]})})
		things.append({"g": Vector2(0, 4), "f": func(): Iso.draw_equipment(self, o, Vector2(0, 4), "shop_window", "se", {"tiers": [[purple, purple], [beige]]})})
		things.append({"g": Vector2(0, 5), "f": func(): Iso.draw_equipment(self, o, Vector2(0, 5), "shop_cabinet", "se")})
		things.append({"g": Vector2(0, 6), "f": func(): Iso.draw_equipment(self, o, Vector2(0, 6), "shop_counter", "se")})
		things.append({"g": Vector2(2, 4), "f": func(): Iso.draw_equipment(self, o, Vector2(2, 4), "warehouse_rack", "se", {"boxes": [1, 2, 2]})})
		things.append({"g": Vector2(4, 5), "f": func(): Iso.draw_equipment(self, o, Vector2(4, 5), "bag")})
		things.append({"g": Vector2(4.3, 5), "f": func(): Iso.draw_equipment(self, o, Vector2(4.3, 5), "bag")})
		things.append({"g": Vector2(5, 6), "f": func(): Iso.draw_equipment(self, o, Vector2(5, 6), "handcart", "sw")})
		things.append({"g": Vector2(7, 6), "f": func(): Iso.draw_equipment(self, o, Vector2(7, 6), "handcart", "se")})
		things.append({"g": Vector2(8, 4), "f": func(): Iso.draw_stall_table(self, o, Vector2(7.2, 4), 2.4, 0.7, 14.0)})
		for j in 3:
			var cell := Vector2(7.2 + 2.4 * (j + 0.5) / 3, 4.38)
			things.append({"g": cell, "f": func():
				var base := Iso.to_screen(cell, o) + Vector2(0, -14)
				for i in 3 - j:
					Iso.draw_scarf_fold(self, base - Vector2(0, i * Iso.FOLD_STEP), [red, navy, beige][i], i * 7 + j)})
		# 人物：每个朝向 × 每帧，发型轮流，一部分围围巾
		var i := 0
		for d in 4:
			for f in 4:
				var g := Vector2(2 + f * 1.2, 7.0 + d * 0.45 - (f % 2) * 0.2) if d < 2 else Vector2(8 + f * 0.9, 2.2 + (d - 2) * 0.7)
				var fit := Iso.outfit_full(i * 131 + 7)
				var facing := 1.0 if d % 2 == 0 else -1.0
				var back := d >= 2
				var phase := 0.0 if f == 0 else float(f) / 6.4 + 0.01
				things.append({"g": g, "f": func(): Iso.draw_person(self, Iso.to_screen(g, o), fit["top"], fit["hair"], facing, phase, back, 1.0, i % Iso.HAIR_STYLES, fit["pants"], fit["scarf"])})
				i += 1
		# 气泡
		things.append({"g": Vector2(11, 7), "f": func():
			var p := Iso.to_screen(Vector2(11, 7), o)
			Iso.draw_person(self, p, Color("#3c7ac8"), Color("#2a2026"), -1.0, 0.0, false, 1.0, Iso.Hair.BOB)
			Iso.draw_bubble(self, p + Vector2(14, -76), "ask")
			Iso.draw_bubble(self, p + Vector2(-38, -76), "haggle")
			Iso.draw_bubble(self, p + Vector2(14, -100), "wait")})
		things.sort_custom(func(a, b): return Iso.depth(a["g"]) < Iso.depth(b["g"]))
		for th in things:
			th["f"].call()
		draw_string(get_theme_default_font(), Vector2(12, 24), "美术陈列室：地面 / 设备 / 人物 4 向 × 4 帧 / 气泡", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _init() -> void:
	var sc := Showcase.new()
	sc.size = Vector2(1280, 720)
	root.add_child(sc)
	sc.queue_redraw()
	for i in 6:
		await process_frame
	var dir := OS.get_environment("SHOTS")
	if dir != "" and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/art_showcase.png" % dir)
	var ok := sc.drawn and not Iso.sprite_meta("eq_shop_shelf_sw").is_empty()
	print("ART_SHOWCASE ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
