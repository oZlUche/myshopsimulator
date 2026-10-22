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


## 找某格的货堆面板（不写 StackView 类型：它引用自动加载 Game，脚本解析时还没有）。
func view_of(box, sl):
	for c in box.get_children():
		if c.has_method("drag_range") and c.slot == sl:
			return c
	return null


## 在货堆面板上按住左键从 a 拖到 b 再松手（拉框）。
func drag(v, a, b):
	for ev in [[true, a], [null, b], [false, b]]:
		var e
		if ev[0] == null:
			e = InputEventMouseMotion.new()
		else:
			e = InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = ev[0]
		e.position = ev[1]
		v._gui_input(e)


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
	# 框选在店里也能用（03 §2.6）：货架上框住最上面两份 → 一份份拆到手上；手上全选 → 点货架空处一起放回
	var shelf = null
	for d2 in displays:
		if d2.stack.height() >= 2:
			shelf = d2
			break
	if shelf != null:
		var e2 = s.inventory.equipment[shelf.equipment_id]
		sh._on_cell(Vector2i(int(e2["pos"][0]), int(e2["pos"][1])))
		await process_frame
		var sv = view_of(sh._closeup, shelf)
		var hs = shelf.stack.height()
		drag(sv, sv._item_rect(hs - 2).get_center(), sv._item_rect(hs - 1).get_center())
		assert(s.inventory.hand().stack.height() == 2 and shelf.stack.height() == hs - 2, "店里框选拆顶两份")
		await process_frame
		var hv = view_of(sh._carry, s.inventory.hand())
		drag(hv, hv._item_rect(0).get_center(), hv._item_rect(1).get_center())
		assert(sh._hand_pick == [0, 1])
		sh._on_slot(shelf.id)
		assert(s.inventory.hand().stack.height() == 0 and shelf.stack.height() == hs, "一起放回货架")
	assert(s.clock.time_of_period == 0.0, "开门前框选也不花时间")

	# ---------- 仓库：搬箱、拆箱、装车 ----------
	sh._go_warehouse()
	await wait_scene("Warehouse")
	var wh = scene()
	assert(s.clock.time_of_period > 0.0, "路上花了时间")
	await shot("s5_warehouse")
	var ops = wh.ops
	var cart = ops.cart()
	assert(s.player.cart_room == "warehouse" and not s.player.pushing_cart, "手推车停在仓库")
	assert(not RoomGrid.walkable(s.inventory, "warehouse", s.player.cart_cell), "停着的车占一格")
	# 抱一箱放到停着的车上（老办法照样行）
	var unload = s.inventory.floor_slot("warehouse", Vector2i(2, 4))
	wh._on_cell(Vector2i(2, 4))
	ops.take(unload.id)
	assert(s.inventory.hand().packages.size() == 1 and s.inventory.hand().packages[0].is_box())
	ops._cart_slot(cart.id)
	assert(cart.packages.size() == 1, "一箱上车")
	# 点停着的车 = 走过去推起来（07 §2.1）；推着车时抱起的箱直接上车，点货架空处就从车上卸
	var t_push = s.clock.time_of_period
	wh._on_cell(s.player.cart_cell)
	assert(s.player.pushing_cart, "推起车了")
	assert(s.clock.time_of_period > t_push, "推车花时间")
	wh._on_cell(Vector2i(2, 4))
	ops.take(unload.id)
	assert(cart.packages.size() == 2 and s.inventory.hand().packages.is_empty(), "推车时箱子直接进车")
	wh._on_cell(Vector2i(0, 0))
	var rack = s.inventory.equipment_slots(s.inventory.equipment_at("warehouse", Vector2i(0, 0)))[0]
	wh._on_slot(rack.id)
	assert(rack.packages.size() == 1 and cart.packages.size() == 1, "从车上卸到仓库货架上")
	await shot("s5b_warehouse_pushing")
	# 拆一箱，看看箱里，拿两包（推着车 → 进车），写标签
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
	assert(cart.packages.size() == 3, "一箱两包在车上：%d" % cart.packages.size())
	var items = ops.menu_items(other.id)
	assert(items.size() >= 3, "箱子菜单")
	ops.package_menu(other.id, Vector2(500, 380))
	await shot("s6_warehouse_menu")
	for c in wh.get_children():
		if c is PopupMenu:
			c.hide()
	# 车上那包撕开，拿一条进散货篓
	ops.open_pack(cart.id)
	ops.item_from_pack(cart.id)
	assert(cart.stack.height() == 1, "车上的开口包拿一条进篓")
	wh._on_cell(Vector2i(4, 2))
	await shot("s7_warehouse_loaded")
	var t_before = s.clock.time_of_period
	wh._go_shop()
	await wait_scene("Shop")
	sh = scene()
	assert(s.clock.time_of_period > t_before)
	assert(s.player.pushing_cart and s.player.cart_room == "shop", "车跟着推回店里")
	assert(sh.ops.player_cell == s.inventory.room_cell("shop", "door"), "从仓库回来站在门口")
	# 卸车：点货架空处先卸篓里的散货，篓空了再把车上那包撕开倒上去
	var free_slot = null
	for d in s.inventory.slots_in("shop", "ShopDisplay"):
		if d.stack.max_height - d.stack.height() >= 2:
			free_slot = d
			break
	if free_slot != null:
		var e = s.inventory.equipment[free_slot.equipment_id]
		sh._on_cell(Vector2i(int(e["pos"][0]), int(e["pos"][1])))
		var h0 = free_slot.stack.height()
		sh._on_slot(free_slot.id)
		assert(free_slot.stack.height() == h0 + 1 and cart.stack.height() == 0, "先卸篓里那条")
		sh._on_slot(free_slot.id)
		assert(free_slot.stack.height() > h0 + 1, "再把车上的包倒上去")
	else:
		sh._on_cell(Vector2i(6, 0))
		sh._on_slot(s.inventory.slots_in("shop", "ShopBackroom")[1].id)
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
							# 讲价时车原地停下了；推起车去拿货，拿到的进散货篓，回来从车上交（07 §2.1）
							assert(not s.player.pushing_cart, "讲价前车原地停下")
							assert(sh.ops.push_cart(), "推起车")
							sh._on_cell(Vector2i(int(e["pos"][0]), int(e["pos"][1])))
							assert(s.player.pushing_cart, "推着车去拿货")
							if at["index"] == sl.stack.height() - 1:
								sh._on_top(sl.id)
							else:
								sh._take_to_hand(sl.id, at["index"], ActionAPI.CAREFUL_PULL)
							assert(cart.stack.index_of(v["item_id"]) >= 0, "拿到的货在车上")
							# 让人走到位再拍（客人到柜台前排队，你走到货架前）
							for i in 30:
								sh._view.step(0.1)
							await shot("s11_fetched")
							var before = s.player.cash
							sh._deliver(v)
							sold = s.player.cash > before
							assert(not s.player.pushing_cart and s.player.cart_room == "shop", "交货前车原地停下")
							assert(RoomGrid.can_park(s.inventory, "shop", s.player.cart_cell) != "", "停着的车占着那格")
							assert(sh.ops.player_cell == ShopSetup.stand_cell(s.inventory), "走回收银台后面")
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
