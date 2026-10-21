class_name ActionAPI
extends RefCounted
## 玩家与员工 AI 共用的动作接口（01 §2.3、03 §6）。所有对真相层的改动都从这里走，
## 并同步写认知层（账本、强化记忆、翻看结果）。actor 目前只有 "player"，员工阶段沿用同一接口。

## 只有展示类槽位有货堆物理；行囊是软包，不会塌。
const PHYSICS_SLOT_TYPES := ["StallTable", "ShopDisplay", "ShopBackroom", "WarehouseShelf"]
## 玩家规范操作时的默认抽取输入（规划阶段 / 自动模拟用）
const CAREFUL_PULL := {"angle_deg": 37.5, "point": "corner", "early_speed": 0.2, "jerk": 0.1}
## 累计抽出货长的一半就算抽出来了（03 §2.1）
const PULL_DONE := 0.5
## 目标每被拉出 1 个货长，上一层被带着横移的比例（再往上逐层叠加）
const ABOVE_DRAG := 0.08
const MAX_SHIFT := 0.25
## 从顶部拿一份 / 往堆顶放一份的固定耗时（秒，03 §2.1）
const TAKE_TOP_SECONDS := 0.5
## NPC 从中间抽一份的耗时（秒）
const NPC_PULL_SECONDS := 2.0

var s: GameState


func _init(state: GameState) -> void:
	s = state


func _slot(slot_id: String) -> Slot:
	return s.inventory.slots.get(slot_id)


func _touch(slot: Slot) -> void:
	s.knowledge.touch_slot(slot, SkillSystem.memory_slots(s.player), s.clock.period)


func _xp(amount: float) -> void:
	s.player.xp_pool += amount
	s.period_stats["xp_earned"] = float(s.period_stats.get("xp_earned", 0.0)) + amount


func bag_free_space() -> int:
	var n := 0
	for sl in s.inventory.slots_of_type("Bag"):
		n += sl.stack.max_height - sl.stack.height()
	return n


## 进货：从本地店买入，直接装进行囊。返回 {ok, reason}。
func purchase(sku_id: String, qty: int, unit_price: float, _actor: String = "player") -> Dictionary:
	var entry: Dictionary = {}
	for e in s.supplier_catalog:
		if e["sku_id"] == sku_id:
			entry = e
	if entry.is_empty():
		return {"ok": false, "reason": "店里没有这款"}
	if qty <= 0 or qty > int(entry["stock"]):
		return {"ok": false, "reason": "库存不足"}
	var total := unit_price * qty
	if total > s.player.cash + 0.0001:
		return {"ok": false, "reason": "现金不够"}
	if qty > bag_free_space():
		return {"ok": false, "reason": "行囊装不下"}
	s.player.cash -= total
	entry["stock"] = int(entry["stock"]) - qty
	for i in qty:
		var it := s.inventory.create_item(sku_id, {"bought_period": s.clock.period, "unit_cost": unit_price, "source": "local_shop"})
		for sl in s.inventory.slots_of_type("Bag"):
			if not sl.stack.is_full():
				place_on_top(it, sl.id)
				break
	s.period_stats["purchases"] = float(s.period_stats["purchases"]) + total
	s.knowledge.add_ledger(s.clock.period, "purchase", -total, "%s ×%d @%.1f" % [DataDB.sku_display_name(sku_id), qty, unit_price])
	s.bus.emit("purchase", {"sku_id": sku_id, "qty": qty, "total": total})
	_xp(1.0 * qty)
	return {"ok": true}


func place_on_top(item: ScarfItem, slot_id: String, _actor: String = "player") -> bool:
	var sl := _slot(slot_id)
	if sl == null or sl.stack.is_full():
		return false
	item.reset_pull()
	sl.stack.settle()
	sl.stack.items.append(item)
	sl.stack.recompute_disorder()
	_touch(sl)
	return true


## 抽取小游戏里拉完一段（按住到松手）：货停在抽出的位置不缩回，上方的货被带歪的状态保留；
## 这段手法单独掷一次倒塌 / 位移判定（03 §2.1）。out: 目标已抽出的比例（±）；
## d: 这段的偏差分；shift: 这段把目标横向带动了多少（±，占货长比例），上方的货按层数传递一部分。
## 返回 {collapsed, displaced, d, p_collapse}。塌了的话目标上面的货全倒在地上，目标本身还在原位露着。
func pull_segment(slot_id: String, index: int, out: float, d: float, shift: float) -> Dictionary:
	var res := {"collapsed": false, "displaced": false, "d": d, "p_collapse": 0.0}
	var sl := _slot(slot_id)
	if sl == null or index < 0 or index >= sl.stack.height():
		return res
	var st := sl.stack
	st.items[index].pull_out = clampf(out, -PULL_DONE, PULL_DONE)
	for i in range(index + 1, st.height()):
		var above: ScarfItem = st.items[i]
		above.shift = clampf(above.shift + shift * ABOVE_DRAG * (i - index), -MAX_SHIFT, MAX_SHIFT)
	var n_above := st.count_above(index)
	if n_above > 0 and PHYSICS_SLOT_TYPES.has(sl.type):
		res = PullPhysics.resolve(d, n_above, s.rng)
		_apply_physics(sl, index + 1, res)
	st.recompute_disorder()
	_touch(sl)
	return res


## 倒塌：第 first 份及以上全部倒在地上（03 §2.2）；没塌但偏差大则整堆被带歪。
func _apply_physics(sl: Slot, first: int, res: Dictionary) -> void:
	var st := sl.stack
	if res["collapsed"]:
		var fallen := st.items.slice(first)
		st.items.resize(first)
		for f in fallen:
			f.reset_pull()
		st.collapsed_pile.append_array(fallen)
		s.period_stats["collapses"] = int(s.period_stats["collapses"]) + 1
		s.bus.emit("stack_collapsed", {"slot_id": sl.id, "count": fallen.size()})
	elif res["displaced"]:
		st.displaced = true


## 从堆中取出第 index 份。顶部直接拿；下层要过抽取结算（03 §2）。
## pull_input 为玩家手法；actor_profile 非空时按客人 / 员工属性采样偏差。
## pull_input.resolved 为真表示小游戏里已经一段段掷过判定，这里直接取走。
## 取走后上面的货不往下沉，留出空隙（03 §2.4）。返回 {item, collapsed, displaced, d}；item 为 null 表示失败。
func pull_item(slot_id: String, index: int, pull_input: Dictionary = CAREFUL_PULL, actor_profile: Dictionary = {}) -> Dictionary:
	var sl := _slot(slot_id)
	if sl == null or index < 0 or index >= sl.stack.height():
		return {"item": null, "collapsed": false, "displaced": false, "d": 0.0}
	var st := sl.stack
	var n_above := st.count_above(index)
	var res := {"collapsed": false, "displaced": false, "d": 0.0}
	if pull_input.get("resolved", false):
		res = {"collapsed": pull_input.get("collapsed", false), "displaced": pull_input.get("displaced", false), "d": 0.0}
	elif n_above > 0 and PHYSICS_SLOT_TYPES.has(sl.type):
		var d := PullPhysics.deviation_from_actor(actor_profile, s.rng) if not actor_profile.is_empty() \
			else PullPhysics.deviation_from_input(pull_input)
		res = PullPhysics.resolve(d, n_above, s.rng)
	var item: ScarfItem = st.items[index]
	st.items.remove_at(index)
	if not pull_input.get("resolved", false):
		_apply_physics(sl, index, res)
	if index < st.height():
		st.items[index].gap_below += 1 + item.gap_below
	item.reset_pull()
	st.recompute_disorder()
	_touch(sl)
	res["item"] = item
	return res


## 从顶部拿一份（03 §2.1）：最上面那份直接拿起，不判定、不会塌，固定耗时 TAKE_TOP_SECONDS。
func take_top(slot_id: String, _actor: String = "player") -> ScarfItem:
	var sl := _slot(slot_id)
	if sl == null or sl.stack.height() == 0:
		return null
	return pull_item(slot_id, sl.stack.height() - 1, {"resolved": true})["item"]


## 从一个堆顶拿一份到手上；手上满了返回 null。
func take_top_to_hand(slot_id: String) -> ScarfItem:
	var h := s.inventory.hand()
	if h.stack.is_full() or slot_id == h.id:
		return null
	var it := take_top(slot_id)
	if it != null:
		place_on_top(it, h.id)
	return it


## NPC（客人自取 / 员工）去拿堆里第 index 份（03 §5）：按性格选拿法。
## 拆顶：把上面的货一份份拿下来，随手放到同类的邻近堆顶（乱度上升），再拿目标，不会塌；
## 邻近堆都放不下时只能硬抽。抽：按执行者属性采样偏差，走同一个倒塌判定。
## 返回 {item, method: "top" | "pull", seconds, collapsed, displaced}。
func npc_fetch(slot_id: String, index: int, profile: Dictionary) -> Dictionary:
	var sl := _slot(slot_id)
	if sl == null or index < 0 or index >= sl.stack.height():
		return {"item": null, "method": "", "seconds": 0.0, "collapsed": false, "displaced": false}
	var n_above := sl.stack.count_above(index)
	if n_above > 0 and PHYSICS_SLOT_TYPES.has(sl.type) and PullPhysics.prefers_take_from_top(profile, s.rng):
		var others := s.inventory.slots_in(sl.location_id, sl.type).filter(func(o): return o.id != slot_id)
		var room := 0
		for o in others:
			room += o.stack.max_height - o.stack.height()
		if room >= n_above:
			var target: ScarfItem = sl.stack.items[index]
			for i in n_above:
				var it := take_top(slot_id)
				for o in others:
					if place_on_top(it, o.id):
						break
			var r := pull_item(slot_id, sl.stack.index_of(target.id), {"resolved": true})
			return {"item": r["item"], "method": "top", "seconds": TAKE_TOP_SECONDS * (2 * n_above + 1),
				"collapsed": false, "displaced": false}
	var res := pull_item(slot_id, index, CAREFUL_PULL, profile)
	return {"item": res["item"], "method": "pull", "seconds": NPC_PULL_SECONDS,
		"collapsed": res["collapsed"], "displaced": res["displaced"]}


## 在两个槽位之间挪一份货：抽出后只能放到目标堆顶（03 §4）。
func move_item(from_slot: String, index: int, to_slot: String, pull_input: Dictionary = CAREFUL_PULL) -> Dictionary:
	var dst := _slot(to_slot)
	if dst == null or dst.stack.is_full():
		return {"ok": false, "reason": "放不下"}
	var r := pull_item(from_slot, index, pull_input)
	if r["item"] == null:
		return {"ok": false, "reason": "没有货"}
	place_on_top(r["item"], to_slot)
	r["ok"] = true
	return r


## 翻看（03 §3）：结果写入认知层，可能认错。有强化记忆悬浮框的槽位不需要翻看。
func peek_item(slot_id: String, index: int) -> Dictionary:
	var sl := _slot(slot_id)
	if sl == null or index < 0 or index >= sl.stack.height():
		return {}
	var item: ScarfItem = sl.stack.items[index]
	var p := Sampler.peek(item, s.rng)
	s.knowledge.perceived[item.id] = p
	return p


## 理货：按给定顺序（item_id 列表，自底向上）重排整堆（03 §4）。
func restack(slot_id: String, order: Array) -> bool:
	var sl := _slot(slot_id)
	if sl == null or order.size() != sl.stack.height():
		return false
	var by_id := {}
	for it in sl.stack.items:
		by_id[it.id] = it
	var new_items: Array[ScarfItem] = []
	for id in order:
		if not by_id.has(id):
			return false
		new_items.append(by_id[id])
	sl.stack.items = new_items
	for it in new_items:
		it.reset_pull()
	sl.stack.displaced = false
	sl.stack.recompute_disorder()
	_touch(sl)
	return true


## 拾起倒地货物放回堆顶（放不下的留在地上）。返回拾起件数。
func pick_up_pile(slot_id: String) -> int:
	var sl := _slot(slot_id)
	if sl == null:
		return 0
	var n := 0
	sl.stack.settle()
	while not sl.stack.collapsed_pile.is_empty() and not sl.stack.is_full():
		sl.stack.items.append(sl.stack.collapsed_pile.pop_back())
		n += 1
	sl.stack.recompute_disorder()
	_touch(sl)
	return n


## 丢弃一份货（摆摊阶段行囊的残货可随时丢弃，01 §6.9）。
func discard(slot_id: String, index: int) -> bool:
	var r := pull_item(slot_id, index)
	if r["item"] == null:
		return false
	s.knowledge.add_ledger(s.clock.period, "discard", 0.0, DataDB.sku_display_name(r["item"].sku_id))
	return true


func write_label(slot_id: String, text: String) -> void:
	s.knowledge.labels[slot_id] = text


## 卖出：从槽位取出该货并收钱。返回 pull 结果 + ok。
func sell(slot_id: String, index: int, price: float, customer: CustomerProfile, reserve: float, pull_input: Dictionary = CAREFUL_PULL) -> Dictionary:
	var r := pull_item(slot_id, index, pull_input)
	var item: ScarfItem = r["item"]
	if item == null:
		return {"ok": false}
	sell_item(item, price, customer, reserve)
	r["ok"] = true
	return r


## 一份已经拿在手里（离开货堆）的货卖给客人：收钱、记账、回购率（客人自取也走这里）。
func sell_item(item: ScarfItem, price: float, customer: CustomerProfile, reserve: float) -> void:
	s.player.cash += price
	var base_price := float(DataDB.sku(item.sku_id)["base_price"])
	s.period_stats["sales"] = int(s.period_stats["sales"]) + 1
	s.period_stats["revenue"] = float(s.period_stats["revenue"]) + price
	s.period_stats["cost_of_goods"] = float(s.period_stats["cost_of_goods"]) + float(item.provenance.get("unit_cost", 0.0))
	s.period_stats["price_ratio_sum"] = float(s.period_stats["price_ratio_sum"]) + price / base_price
	s.customers.record_purchase(customer, price, reserve, float(SkillSystem.haggle_mods(s.player)["loyalty_bonus"]))
	s.knowledge.add_ledger(s.clock.period, "sale", price, DataDB.sku_display_name(item.sku_id))
	s.bus.emit("sale", {"item_id": item.id, "sku_id": item.sku_id, "price": price, "customer_id": customer.id})
	_xp(4.0 + price * 0.05)


## 收摊：摊位上的货（含地上的）全部收回行囊。返回装不下而被丢掉的件数。
func pack_up() -> int:
	var lost := 0
	for sl in s.inventory.slots_of_type("StallTable") + s.inventory.slots_of_type("Hand"):
		var all: Array[ScarfItem] = []
		all.append_array(sl.stack.items)
		all.append_array(sl.stack.collapsed_pile)
		sl.stack.items.clear()
		sl.stack.collapsed_pile.clear()
		sl.stack.displaced = false
		sl.stack.recompute_disorder()
		for it in all:
			var placed := false
			for bag in s.inventory.slots_of_type("Bag"):
				if place_on_top(it, bag.id):
					placed = true
					break
			if not placed:
				lost += 1
				s.knowledge.add_ledger(s.clock.period, "discard", 0.0, "行囊装不下：" + DataDB.sku_display_name(it.sku_id))
	return lost


## 购置设备（01 §4.9）：扣现金，向场所注入槽位。摆摊设备只能在摆摊阶段买。
func buy_equipment(def_id: String, location_id: String) -> Dictionary:
	var def: Dictionary = DataDB.equipment().get(def_id, {})
	if def.is_empty():
		return {"ok": false, "reason": "没有这种设备"}
	var phase: String = def.get("phase", "any")
	if phase != "any" and phase != s.player.phase:
		return {"ok": false, "reason": "当前阶段用不上"}
	var price := float(def.get("price", 0.0))
	if price > s.player.cash + 0.0001:
		return {"ok": false, "reason": "现金不够"}
	s.player.cash -= price
	var eid := s.inventory.install_equipment(def_id, location_id)
	s.knowledge.add_ledger(s.clock.period, "equipment", -price, def.get("name", def_id))
	s.bus.emit("equipment_bought", {"def_id": def_id, "equipment_id": eid})
	return {"ok": true, "equipment_id": eid}
