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
	for t in s.inventory.slots_of_type("StallTable"):
		for b in s.inventory.slots_of_type("Bag"):
			while not t.stack.is_full() and b.stack.height() > 0:
				st._selected = {"slot_id": b.id, "index": b.stack.height()-1}
				st._on_slot(t.id)
	st._on_peek(s.inventory.slots_of_type("StallTable")[0].id, 0)
	# 抽取小游戏：从第 1 格最底下抽一份放到第 3 格
	var tables = s.inventory.slots_of_type("StallTable")
	var before = tables[0].stack.height()
	st._selected = {"slot_id": tables[0].id, "index": 0}
	st._on_slot(tables[2].id)
	assert(st._minigame != null, "从堆底抽货应弹出小游戏")
	await good_pull(st, true)
	assert(st._minigame == null, "好手法应能把货拉出来")
	assert(tables[0].stack.height() + tables[0].stack.collapsed_pile.size() == before - 1)
	# 拉一半停手：货停在外面不缩回；再打开接着拉，累计过半就抽出来
	var t1 = tables[1]
	if t1.stack.height() >= 2 and not tables[2].stack.is_full():
		var h1 = t1.stack.height()
		var target = t1.stack.items[0]
		st._selected = {"slot_id": t1.id, "index": 0}
		st._on_slot(tables[2].id)
		await good_pull(st, false, 9)
		var release = InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		st._minigame._gui_input(release)
		await shot("3c_pull_paused")
		st._minigame._stop()
		assert(st._minigame == null)
		assert(t1.stack.height() == h1, "停手不该把货抽走")
		assert(target.pull_out < 0.0 and target.pull_out > -0.5, "停手后货停在外面 %f" % target.pull_out)
		await shot("3d_stack_after_pause")
		st._selected = {"slot_id": t1.id, "index": 0}
		st._on_slot(tables[2].id)
		assert(is_equal_approx(st._minigame._out, target.pull_out), "再打开应接着上次的进度")
		await good_pull(st)
		assert(st._minigame == null)
		assert(t1.stack.height() + t1.stack.collapsed_pile.size() == h1 - 1)
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
	st._haggle.offer_price(st._haggle.asking_price, s.rng)
	st._after_haggle_step()
	await shot("5_haggle_step")
	st._haggle.accept_customer_offer()
	st._refresh_haggle()
	st._end_haggle()
	if st._minigame != null:
		await good_pull(st)
	for i in 600: st._process(1.0)
	await shot("6_stall_later")
	st._on_main_button()
	for i in 8: await process_frame
	await shot("7_settlement")
	var ok = s.clock.period == 2 and current_scene.name == "Settlement"
	print("UI_SMOKE ", "PASS" if ok else "FAIL", " period=", s.clock.period)
	quit(0 if ok else 1)
