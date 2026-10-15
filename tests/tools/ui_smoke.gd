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
	for i in 600: st._process(1.0)
	await shot("6_stall_later")
	st._on_main_button()
	for i in 8: await process_frame
	await shot("7_settlement")
	var ok = s.clock.period == 2 and current_scene.name == "Settlement"
	print("UI_SMOKE ", "PASS" if ok else "FAIL", " period=", s.clock.period)
	quit(0 if ok else 1)
