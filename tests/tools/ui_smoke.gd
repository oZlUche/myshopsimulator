extends SceneTree
## 界面冒烟测试：脚本化走一遍 新游戏 → 规划 → 街区 → 摆货 → 开张 → 议价 → 收摊 → 结算。
## CI 里无界面运行（只检查脚本不报错）；本地有显示时设 SHOTS=目录 可以顺便截图：
##   SHOTS=/tmp/shots xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/tools/ui_smoke.gd
var G
func shot(name):
	for i in 4: await process_frame
	var dir := OS.get_environment("SHOTS")
	if dir != "" and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])
## 用好手法（按角落、斜向约 40°、先慢后快）把当前小游戏里的货拉出来。
func good_pull(st, take_shot := false, max_steps := 200):
	var mg = st._minigame
	mg.set_process(false)  # 测试直接喂轨迹，不读真实鼠标
	for i in 3: await process_frame
	var tr = mg._target_rect()
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = tr.position + Vector2(4, 3)
	mg._gui_input(press)
	var p = press.position
	var speeds = [60, 80, 100, 140, 200, 280, 380, 480, 560, 600]
	var k = 0
	while st._minigame != null and k < max_steps:
		p += Vector2(-1, -0.84).normalized() * speeds[mini(k, speeds.size() - 1)] * 0.05
		mg._elapsed += 0.05
		mg.drag_step(p, 0.05)
		if k == 6 and take_shot:
			await shot("3b_pull_minigame")
		k += 1

func scene():
	return current_scene
func _init() -> void:
	await process_frame
	G = root.get_node("Game")
	G.new_game(12345)
	for i in 5: await process_frame
	await shot("1_planning")
	var s = G.state
	assert(current_scene.name == "Planning")
	var api = ActionAPI.new(s)
	for e in s.supplier_catalog.slice(0, 4):
		api.purchase(e["sku_id"], 2, float(e["unit_price"]))
	scene()._tabs.current_tab = 3
	scene()._refresh()
	await shot("2_skills")
	scene()._tabs.current_tab = 2
	await shot("2b_prices")
	G.goto("street")
	for i in 5: await process_frame
	await shot("3_street")
	var x = 0.5
	while not s.street.can_place(x): x += 0.5
	G.stall_x = x
	G.goto("stall")
	for i in 5: await process_frame
	var st = scene()
	var hand = s.inventory.hand()
	# 摆货：点行囊堆顶拿到手上，再点摊位格空处放下
	for t in s.inventory.slots_of_type("StallTable"):
		for b in s.inventory.slots_of_type("Bag"):
			while not t.stack.is_full() and b.stack.height() > 0:
				st._on_top(b.id)
				st._on_slot(t.id)
	assert(hand.stack.height() == 0)
	st._on_peek(s.inventory.slots_of_type("StallTable")[0].id, 0)
	var tables = s.inventory.slots_of_type("StallTable")
	# 从顶部拿：连点两下拿两份到手上，不开小游戏，不会塌；再放回去
	var h0 = tables[1].stack.height()
	st._on_top(tables[1].id)
	st._on_top(tables[1].id)
	assert(st._minigame == null and hand.stack.height() == mini(2, h0))
	await shot("3a_hand")
	while hand.stack.height() > 0:
		st._on_slot(tables[1].id)
	assert(tables[1].stack.height() == h0)
	# 抽取小游戏：点第 1 格最底下那份的侧面，抽到手上，再放到第 3 格
	var before = tables[0].stack.height()
	st._on_strip(tables[0].id, 0)
	assert(st._minigame != null, "从堆底抽货应弹出小游戏")
	await good_pull(st, true)
	assert(st._minigame == null, "好手法应能把货拉出来")
	assert(hand.stack.height() == 1)
	st._on_slot(tables[2].id)
	assert(hand.stack.height() == 0)
	assert(tables[0].stack.height() + tables[0].stack.collapsed_pile.size() == before - 1)
	# 拉一半停手：货停在外面不缩回；再打开接着拉，累计过半就抽出来
	var t1 = tables[1]
	if t1.stack.height() >= 2 and not tables[2].stack.is_full():
		var h1 = t1.stack.height()
		var target = t1.stack.items[0]
		st._on_strip(t1.id, 0)
		await good_pull(st, false, 9)
		var release = InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		st._minigame._gui_input(release)
		await shot("3c_pull_paused")
		st._minigame._stop()
		assert(st._minigame == null)
		assert(t1.stack.height() + t1.stack.collapsed_pile.size() == h1, "停手不该把货抽走")
		assert(target.pull_out < 0.0 and target.pull_out > -0.5, "停手后货停在外面 %f" % target.pull_out)
		await shot("3d_stack_after_pause")
		st._on_strip(t1.id, 0)
		assert(is_equal_approx(st._minigame._out, target.pull_out), "再打开应接着上次的进度")
		await good_pull(st)
		assert(st._minigame == null)
		st._on_slot(tables[2].id)
		assert(t1.stack.height() + t1.stack.collapsed_pile.size() == h1 - 1)
		await shot("3e_gap_after_pull")
	st._on_main_button()
	var guard = 0
	while guard < 3000:
		guard += 1
		st._process(0.5)
		var asking = st.session.visitors.filter(func(v): return v["state"] == "asking")
		if asking.size() > 0 and st._haggle == null:
			st._start_haggle(asking[0])
			break
	st._refresh_all()
	await shot("4_stall_haggle")
	# 先用一招说服（按钮行），再报个低价保证谈成（P 模型下报高可能吓跑）
	st._haggle.use_strategy("color", s.rng)
	st._after_haggle_step()
	await shot("5_haggle_step")
	assert(st._haggle.result == "ongoing" or st._haggle.result == "deal", "一招之后不该就走：%s" % st._haggle.result)
	if st._haggle.result == "ongoing":
		if st._haggle.customer_offer > 0.0:
			st._haggle.accept_customer_offer()
		else:
			st._haggle.offer_price(1.0, s.rng)
	st._refresh_haggle()
	assert(st._haggle.result == "deal", "低价应谈成：%s" % st._haggle.result)
	var buyer = st._haggle_visitor
	st._end_haggle()
	assert(buyer["state"] == "waiting_item", "谈成后应等你拿货，不自动出货：%s" % buyer["state"])
	var sales0 = s.period_stats["sales"]
	# 手上空着点他：只提示他要哪份，不扣等待时间
	while hand.stack.height() > 0:
		st._on_slot(tables[2].id)
	var w0 = buyer["wait"]
	st._on_visitor_clicked(buyer)
	assert(buyer["state"] == "waiting_item" and buyer["wait"] == w0)
	# 找到他要的那份拿到手上（在顶上就拿顶，否则抽），再点他交货
	var want = buyer["want"][0]
	var loc = st.session.locate(want["item_id"])
	if loc.is_empty():
		loc = st.session.find_sku(want["sku_id"])
	var sl = s.inventory.slots[loc["slot_id"]]
	if loc["index"] == sl.stack.height() - 1:
		st._on_top(sl.id)
	else:
		st._on_strip(sl.id, loc["index"])
		if st._minigame != null:
			await good_pull(st)
	assert(hand.stack.height() == 1)
	st._refresh_all()
	await shot("5b_waiting_item")
	st._on_visitor_clicked(buyer)
	assert(s.period_stats["sales"] == sales0 + 1, "交货后才算卖出")
	assert(hand.stack.height() == 0)
	for i in 300: st._process(1.0)
	await shot("6_stall_later")
	# 卖光：把剩下的货都清掉、客人散去，应自动收摊进结算，并标记卖光
	if st._haggle != null:
		st._haggle.choose_option("suggest_other", s.rng)
		st._end_haggle()
	st.session.close()
	for t in ["StallTable", "Hand", "Bag"]:
		for x2 in s.inventory.slots_of_type(t):
			x2.stack.items.clear()
			x2.stack.collapsed_pile.clear()
	st.speed = 1.0
	for i in 8:
		if current_scene != st:
			break
		st._process(1.0)
	for i in 8: await process_frame
	await shot("7_settlement")
	var ok = s.clock.period == 2 and current_scene.name == "Settlement" and G.last_report.get("sold_out", false)
	print("UI_SMOKE ", "PASS" if ok else "FAIL", " period=", s.clock.period, " sold_out=", G.last_report.get("sold_out", false))
	quit(0 if ok else 1)
