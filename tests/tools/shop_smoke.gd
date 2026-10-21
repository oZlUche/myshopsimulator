extends SceneTree
## 开店冒烟测试（07）：试玩开店 → 规划 → 店里摆设备、拆包上架 → 去仓库搬箱、拆箱、装车 → 推车回店卸货
## → 开门营业、讲价、走到货架拿货交货 → 打烊结算。
## 本地有显示时设 SHOTS=目录 顺便截图：
##   SHOTS=/tmp/shots xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/tools/shop_smoke.gd
var G


func shot(name):
	for i in 4: await process_frame
	var dir := OS.get_environment("SHOTS")
	if dir != "" and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func scene():
	return current_scene


func wait_scene(name):
	for i in 30:
		await process_frame
		if current_scene != null and current_scene.name == name:
			for j in 3: await process_frame
			return
	assert(false, "没进到 " + name)


func _init() -> void:
	await process_frame
	G = root.get_node("Game")
	G.new_preview_game(4242)
	await wait_scene("Planning")
	var s = G.state
	assert(s.player.phase == "shop")
	assert(G.save_path == G.PREVIEW_SAVE_PATH)
	await shot("s1_planning")

	# ---------- 店里：摆设备、拆包上架（开门前时间不走） ----------
	scene()._go_room("shop")
	await wait_scene("Shop")
	var sh = scene()
	await shot("s2_shop")
	sh._toggle_layout()
	assert(sh.ops.layout_mode)
	sh.ops.start_placing("mannequin")
	sh._view.hover_cell = Vector2i(5, 1)
	sh._view.placing_ok = true
	await shot("s3_shop_layout")
	var cash0 = s.player.cash
	sh._on_cell(Vector2i(5, 1))
	assert(s.inventory.equipment_at("shop", Vector2i(5, 1)) != "", "模特摆上了")
	assert(s.player.cash < cash0)
	sh.ops.cancel_placing()
	sh._toggle_layout()
	assert(not sh.ops.layout_mode)
	var cab = s.inventory.slots_in("shop", "ShopBackroom")[0]
	var displays = s.inventory.slots_in("shop", "ShopDisplay")
	var di = 0
	while not cab.packages.is_empty() and di < displays.size():
		sh._on_cell(Vector2i(6, 0))
		sh.ops.take(cab.id)
		assert(not s.inventory.hand().packages.is_empty(), "从货柜拿起一包")
		var d = displays[di]
		var e = s.inventory.equipment[d.equipment_id]
		sh._on_cell(Vector2i(int(e["pos"][0]), int(e["pos"][1])))
		while not s.inventory.hand().packages.is_empty() and di < displays.size():
			d = displays[di]
			sh._on_slot(d.id)
			if s.inventory.hand().packages.is_empty() or d.stack.is_full():
				di += 1
		# 剩下的包放回货柜
		if not s.inventory.hand().packages.is_empty():
			sh._on_cell(Vector2i(6, 0))
			sh._on_slot(cab.id)
	assert(s.clock.time_of_period == 0.0, "开门前干活不花时间")
	assert(not sh.session.table_empty(), "货架上有货了")
	await shot("s4_shop_stocked")

	# ---------- 仓库：搬箱、拆箱、装车 ----------
	sh._go_warehouse()
	await wait_scene("Warehouse")
	var wh = scene()
	assert(s.clock.time_of_period > 0.0, "路上花了时间")
	await shot("s5_warehouse")
	var ops = wh.ops
	var cart = ops.cart()
	var unload = s.inventory.floor_slot("warehouse", Vector2i(2, 4))
	wh._on_cell(Vector2i(2, 4))
	ops.take(unload.id)
	assert(s.inventory.hand().packages.size() == 1 and s.inventory.hand().packages[0].is_box())
	ops._cart_slot(cart.id)
	assert(cart.packages.size() == 1, "一箱上车")
	# 第二箱码到货架上
	wh._on_cell(Vector2i(2, 4))
	ops.take(unload.id)
	wh._on_cell(Vector2i(0, 0))
	var rack = s.inventory.equipment_slots(s.inventory.equipment_at("warehouse", Vector2i(0, 0)))[0]
	wh._on_slot(rack.id)
	assert(rack.packages.size() == 1, "码到仓库货架上")
	# 拆一箱，看看箱里，拿两包，写标签
	var other = s.inventory.floor_slot("warehouse", Vector2i(3, 4))
	wh._on_cell(Vector2i(3, 4))
	var box = other.packages[-1]
	if box.sealed:
		ops.open_box(other.id)
	ops.look_into_box(other.id)
	ops.write_label(box.id, "测试箱")
	assert(s.knowledge.labels[box.id] == "测试箱")
	ops.pack_from_box(other.id)
	ops.pack_from_box(other.id)
	assert(s.inventory.hand().packages.size() == 2)
	var items = ops.menu_items(other.id)
	assert(items.size() >= 3, "箱子菜单")
	ops.package_menu(other.id, Vector2(500, 380))
	await shot("s6_warehouse_menu")
	for c in wh.get_children():
		if c is PopupMenu:
			c.hide()
	ops._cart_slot(cart.id)
	ops._cart_slot(cart.id)
	assert(cart.packages.size() == 3, "一箱两包上车：%d" % cart.packages.size())
	wh._on_cell(Vector2i(4, 2))
	await shot("s7_warehouse_loaded")
	var t_before = s.clock.time_of_period
	wh._go_shop()
	await wait_scene("Shop")
	sh = scene()
	assert(s.clock.time_of_period > t_before)
	assert(sh.ops.player_cell == s.inventory.room_cell("shop", "door"), "从仓库回来站在门口")
	# 卸车：一包倒到货架上，一箱堆到店里地上
	sh.ops.walk_to_cart()
	sh.ops.take(cart.id)
	var free_slot = null
	for d in s.inventory.slots_in("shop", "ShopDisplay"):
		if d.stack.height() == 0:
			free_slot = d
			break
	if free_slot != null:
		var e = s.inventory.equipment[free_slot.equipment_id]
		sh._on_cell(Vector2i(int(e["pos"][0]), int(e["pos"][1])))
		sh._on_slot(free_slot.id)
	else:
		sh._on_cell(Vector2i(6, 0))
		sh._on_slot(s.inventory.slots_in("shop", "ShopBackroom")[1].id)
	assert(s.inventory.hand().packages.size() <= 1)
	await shot("s8_shop_unloaded")

	# ---------- 开门营业 ----------
	sh._on_main_button()
	assert(sh.phase == sh.Phase.OPEN)
	var sold = false
	var guard = 0
	var shot_open = false
	while guard < 4000 and not sold and sh.phase == sh.Phase.OPEN:
		guard += 1
		sh._process(0.5)
		if not shot_open and sh.session.visitors.size() >= 2:
			shot_open = true
			for i in 20:
				sh._view.step(0.1)
			await shot("s9_shop_open")
		var asking = sh.session.visitors.filter(func(v): return v["state"] == "asking")
		if asking.size() > 0 and sh._haggle == null:
			sh._start_haggle(asking[0])
			if sh._haggle != null:
				await shot("s10_haggle")
				var h = sh._haggle
				var tries = 0
				while h.result == "ongoing" and tries < 8:
					tries += 1
					if h.customer_offer > 0.0:
						h.accept_customer_offer()
					else:
						h.offer_price(h.asking_price * 0.8, s.rng)
				sh._after_haggle_step()
				if h.result != "ongoing":
					var v = sh._haggle_visitor
					sh._end_haggle()
					if v["state"] == "waiting_item":
						var at = sh.session.locate(v["item_id"])
						if not at.is_empty():
							var sl = s.inventory.slots[at["slot_id"]]
							var e = s.inventory.equipment[sl.equipment_id]
							sh._on_cell(Vector2i(int(e["pos"][0]), int(e["pos"][1])))
							if at["index"] == sl.stack.height() - 1:
								sh._on_top(sl.id)
							else:
								sh._take_to_hand(sl.id, at["index"], ActionAPI.CAREFUL_PULL)
							await shot("s11_fetched")
							var before = s.player.cash
							sh._deliver(v)
							sold = s.player.cash > before
	assert(sold, "店里卖出去一单")
	await shot("s12_after_sale")
	sh._pack_up()
	await wait_scene("Settlement")
	await shot("s13_settlement")
	assert(G.has_save(G.PREVIEW_SAVE_PATH))
	var r = SaveManager.new().load_game(G.PREVIEW_SAVE_PATH)
	assert(r["ok"], "预览存档读得回来")
	assert(r["state"].player.phase == "shop")
	print("SHOP_SMOKE PASS")
	quit()
