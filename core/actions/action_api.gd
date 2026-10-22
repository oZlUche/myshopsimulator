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


## 拆顶、放顶、抱起 / 放下箱包的耗时（【搬运】Lv2 ×0.8，02 §2.10）。
func handle_seconds(base: float) -> float:
	return base * float(SkillSystem.carry_mods(s.player)["handle_time_mult"])


## 走路速度倍率（07 §2）：抱着箱子 ×0.6（【搬运】Lv4 ×0.75），抱两箱 ×0.5；空手、拿散货、拿包不变。
## 推着手推车 ×0.8（Lv4 ×0.9），车上装多少都一样（07 §2.1）。
func walk_speed_mult() -> float:
	var mods := SkillSystem.carry_mods(s.player)
	if s.player.pushing_cart and s.inventory.cart() != null:
		return float(mods["cart_walk_mult"])
	var h := s.inventory.hand()
	var boxes := 0
	for p in h.packages:
		if p.is_box():
			boxes += 1
	if boxes >= 2:
		return 0.5
	return float(mods["box_walk_mult"]) if boxes == 1 else 1.0


## 现在东西拿到哪儿（07 §2.1）：推着手推车时是车（车板放箱包、散货进散货篓），否则是手上。
## 拿、放、交货都只认它。推车时手扶着车把，没有另外的「手上」。
func carrier() -> Slot:
	if s.player.pushing_cart:
		var c := s.inventory.cart()
		if c != null:
			return c
	return s.inventory.hand()


## 推起 / 停下手推车的耗时（秒，07 §2.1）
const CART_PUSH_SECONDS := 2.0


## 推起停着的手推车（07 §2.1）：手上的东西顺手放到车上（箱包上车板、散货进篓），放不下就推不起来。
## 走到车跟前由场景负责。返回 {ok, reason, moved}。
func push_cart() -> Dictionary:
	var c := s.inventory.cart()
	if c == null:
		return {"ok": false, "reason": "没有手推车", "moved": 0}
	if s.player.pushing_cart:
		return {"ok": false, "reason": "已经推着了", "moved": 0}
	var h := s.inventory.hand()
	var units := c.package_units()
	for p in h.packages:
		units += p.units()
	if units > c.pkg_capacity or c.stack.height() + h.stack.height() > c.stack.max_height:
		return {"ok": false, "reason": "手上的东西车上放不下，先放到别处", "moved": 0}
	var moved := h.packages.size() + h.stack.height()
	for p in h.packages:
		c.packages.append(p)
	h.packages.clear()
	for it in h.stack.items:
		place_on_top(it, c.id)
	h.stack.items.clear()
	s.player.pushing_cart = true
	return {"ok": true, "reason": "", "moved": moved}


## 把推着的车停在 loc 的 cell，车头朝 facing（07 §2.1）。门口、收银台后面不能停。返回 {ok, reason}。
func park_cart(loc: String, cell: Vector2i, facing: String = "sw") -> Dictionary:
	if not s.player.pushing_cart:
		return {"ok": false, "reason": "没在推车"}
	s.player.pushing_cart = false
	var why := RoomGrid.can_park(s.inventory, loc, cell)
	if why != "":
		s.player.pushing_cart = true
		return {"ok": false, "reason": why}
	s.player.cart_room = loc
	s.player.cart_cell = cell
	s.player.cart_facing = facing
	return {"ok": true, "reason": ""}


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
	if sl == null or sl.stack.is_full() or (not sl.packages.is_empty() and not sl.mixes()):
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
## hi ≥ index 时是整块抽取 [index, hi]（03 §2.6）：整块一起出来，压在块上面的才会塌，块越厚越容易塌。
## 返回 {collapsed, displaced, d, p_collapse}。塌了的话目标上面的货全倒在地上，目标本身还在原位露着。
func pull_segment(slot_id: String, index: int, out: float, d: float, shift: float, hi: int = -1) -> Dictionary:
	var res := {"collapsed": false, "displaced": false, "d": d, "p_collapse": 0.0}
	var sl := _slot(slot_id)
	if sl == null or index < 0 or index >= sl.stack.height():
		return res
	var st := sl.stack
	var top := clampi(maxi(hi, index), index, st.height() - 1)
	for i in range(index, top + 1):
		st.items[i].pull_out = clampf(out, -PULL_DONE, PULL_DONE)
	for i in range(top + 1, st.height()):
		var above: ScarfItem = st.items[i]
		above.shift = clampf(above.shift + shift * ABOVE_DRAG * (i - top), -MAX_SHIFT, MAX_SHIFT)
	var n_above := st.count_above(top)
	if n_above > 0 and PHYSICS_SLOT_TYPES.has(sl.type):
		res = PullPhysics.resolve(d, n_above, s.rng, PullPhysics.block_alpha_mult(top - index + 1))
		_apply_physics(sl, top + 1, res)
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


## 从一个堆顶拿 count 份到手上（框选批量拆顶就是单份拆顶重复 count 次，03 §2.6），拿到手上满为止。
## 返回最后拿起的那份（现在在手上最上面）；一份都没拿到返回 null。散货上限看【搬运】（02 §2.10）。
func take_top_to_hand(slot_id: String, count: int = 1) -> ScarfItem:
	var h := carrier()
	var last: ScarfItem = null
	if slot_id == h.id or (not h.packages.is_empty() and not h.mixes()):
		return null
	for i in count:
		if h.stack.is_full():
			break
		var it := take_top(slot_id)
		if it == null:
			break
		place_on_top(it, h.id)
		last = it
	return last


## 手上（推车时是散货篓）还能拿几条散货；抱着箱包时为 0。
func hand_room() -> int:
	var h := carrier()
	return 0 if not h.packages.is_empty() and not h.mixes() else h.stack.max_height - h.stack.height()


## 整块抽取（03 §2.6）：把 [lo, hi] 这一段当一块从堆里抽出来，按原顺序进手上（块最上面那份在手上最上面）。
## 块得放得进手上（≤ 手上余量），否则不动、返回 item 为 null。判定同 pull_item：pull_input.resolved 为真
## 表示小游戏里已经一段段掷过；否则按手法 / 执行者属性掷一次，倒塌系数按块厚加大。
## 取走后上面的货不往下沉，留出 n 层空隙。返回 {items, item（块最上面那份）, collapsed, displaced, d}。
func pull_block(slot_id: String, lo: int, hi: int, pull_input: Dictionary = CAREFUL_PULL, actor_profile: Dictionary = {}) -> Dictionary:
	var out := {"items": [], "item": null, "collapsed": false, "displaced": false, "d": 0.0}
	var sl := _slot(slot_id)
	var h := carrier()
	if sl == null or slot_id == h.id or lo < 0 or hi < lo or hi >= sl.stack.height():
		return out
	var n := hi - lo + 1
	if n > hand_room():
		return out
	var st := sl.stack
	var res := {"collapsed": false, "displaced": false, "d": 0.0}
	if pull_input.get("resolved", false):
		res = {"collapsed": pull_input.get("collapsed", false), "displaced": pull_input.get("displaced", false), "d": 0.0}
	elif st.count_above(hi) > 0 and PHYSICS_SLOT_TYPES.has(sl.type):
		var d := PullPhysics.deviation_from_actor(actor_profile, s.rng) if not actor_profile.is_empty() \
			else PullPhysics.deviation_from_input(pull_input)
		res = PullPhysics.resolve(d, st.count_above(hi), s.rng, PullPhysics.block_alpha_mult(n))
	var block: Array[ScarfItem] = []
	var gaps := 0
	for i in n:
		var it: ScarfItem = st.items[lo]
		st.items.remove_at(lo)
		gaps += 1 + it.gap_below
		block.append(it)
	if not pull_input.get("resolved", false):
		_apply_physics(sl, lo, res)
	if lo < st.height():
		st.items[lo].gap_below += gaps
	st.recompute_disorder()
	_touch(sl)
	for it in block:
		it.reset_pull()
		place_on_top(it, h.id)
	res["items"] = block
	res["item"] = block[-1]
	return res


## 批量翻看（03 §2.6）：对 [lo, hi] 逐份 peek_item，每份 2 秒（时间由场景花）。返回每份的翻看结果。
func peek_range(slot_id: String, lo: int, hi: int, _actor: String = "player") -> Array:
	var out: Array = []
	for i in range(lo, hi + 1):
		var p := peek_item(slot_id, i)
		if not p.is_empty():
			out.append(p)
	return out


## 把手上第 lo 份起的 count 份按原顺序依次放到某堆顶（03 §2.6 手上框选后批量放下）；lo < 0 表示最上面 count 份。
## 放不下的留在手上。返回放下了几份（每份 TAKE_TOP_SECONDS，由场景花）。
func place_from_carrier(slot_id: String, count: int, lo: int = -1) -> int:
	var h := carrier()
	var dst := _slot(slot_id)
	if dst == null or slot_id == h.id or count <= 0:
		return 0
	var start := h.stack.height() - count if lo < 0 else lo
	start = clampi(start, 0, h.stack.height())
	var end := mini(start + count, h.stack.height())
	var moving: Array[ScarfItem] = []
	for i in range(start, end):
		moving.append(h.stack.items[i])
	var placed := 0
	for it in moving:
		if dst.stack.is_full() or (not dst.packages.is_empty() and not dst.mixes()):
			break
		h.stack.items.erase(it)
		place_on_top(it, slot_id)
		placed += 1
	if placed > 0:
		h.stack.settle()
		h.stack.recompute_disorder()
	return placed


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


## 手写标签（认知层）：货堆格子、箱、包都能写，key 是槽位或整箱整包的 ID。空字符串 = 擦掉。
func write_label(slot_id: String, text: String) -> void:
	if text.strip_edges() == "":
		s.knowledge.labels.erase(slot_id)
	else:
		s.knowledge.labels[slot_id] = text


# ---------- 整箱整包（07 §2） ----------
const OPEN_BOX_SECONDS := 8.0
const LOOK_INTO_BOX_SECONDS := 2.0
const OPEN_PACK_SECONDS := 3.0
const UNPACK_PER_ITEM_SECONDS := 0.5
const LABEL_SECONDS := 2.0
const MOVE_PACKAGE_SECONDS := 2.0


## 把某格最上面那个箱 / 包抱到手上。手上得没拿着散货，而且抱得下（箱、包不混拿，各按【搬运】的上限）。返回 {ok, reason, package}。
func take_package(slot_id: String) -> Dictionary:
	var sl := _slot(slot_id)
	var h := carrier()
	if sl == null or sl.packages.is_empty():
		return {"ok": false, "reason": "这里没有箱子或包"}
	if slot_id == h.id:
		return {"ok": false, "reason": "已经在车上了"}
	if h.stack.height() > 0 and not h.mixes():
		return {"ok": false, "reason": "手上拿着散货，先放下"}
	var p: Package = sl.packages[-1]
	if not h.can_hold(p):
		if h.mixes():
			return {"ok": false, "reason": "车上放不下了，一车最多 %d 箱，或 1 箱 + 3 包，或 %d 包" % [h.pkg_capacity / int(Package.UNITS["box"]), h.pkg_capacity]}
		return {"ok": false, "reason": "抱不下了，一次只能抱 %d 箱或 %d 包，不能混着抱" % [h.kind_limits["box"], h.kind_limits["pack"]]}
	sl.packages.pop_back()
	h.packages.append(p)
	return {"ok": true, "package": p}


## 把手上最上面那个箱 / 包放到某格顶上（地堆最高 4 箱，07 §2）。返回 {ok, reason}。
func put_package(slot_id: String) -> Dictionary:
	var sl := _slot(slot_id)
	var h := carrier()
	if sl == null or h.packages.is_empty():
		return {"ok": false, "reason": "手上没有箱子或包"}
	var p: Package = h.packages[-1]
	if sl.type == "Floor" and RoomGrid.is_aisle(s.inventory, sl.location_id, sl.grid_pos):
		return {"ok": false, "reason": "这格是过道，不能堆东西"}
	if not sl.can_hold(p):
		return {"ok": false, "reason": "放不下" if sl.pkg_capacity > 0 else "这里不能放整箱整包"}
	h.packages.pop_back()
	sl.packages.append(p)
	return {"ok": true}


## 在两个格子之间搬一个箱 / 包（手推车装卸、自动模拟用）：from 最上面那个放到 to 顶上。
func move_package(from_slot: String, to_slot: String) -> Dictionary:
	var a := _slot(from_slot)
	var b := _slot(to_slot)
	if a == null or b == null or a.packages.is_empty():
		return {"ok": false, "reason": "这里没有箱子或包"}
	if b.type == "Floor" and RoomGrid.is_aisle(s.inventory, b.location_id, b.grid_pos):
		return {"ok": false, "reason": "这格是过道，不能堆东西"}
	if not b.can_hold(a.packages[-1]):
		return {"ok": false, "reason": "放不下"}
	b.packages.append(a.packages.pop_back())
	return {"ok": true}


## 拆开某格（含手上）最上面那箱。返回 false 表示上面不是封着的箱。
func open_box(slot_id: String) -> bool:
	var sl := _slot(slot_id)
	if sl == null or sl.packages.is_empty() or not sl.packages[-1].is_box() or not sl.packages[-1].sealed:
		return false
	sl.packages[-1].sealed = false
	s.bus.emit("box_opened", {"package_id": sl.packages[-1].id})
	return true


## 撕开某格（含手上）最上面那包的袋子，之后能一条条拿。返回 false 表示上面不是封着的包。
func open_pack(slot_id: String) -> bool:
	var sl := _slot(slot_id)
	if sl == null or sl.packages.is_empty() or sl.packages[-1].is_box() or not sl.packages[-1].sealed:
		return false
	sl.packages[-1].sealed = false
	return true


## 看一眼包：隔着袋子看最上面那条（按翻看规则，可能认错，03 §3）。结果写进认知层。
func look_at_pack(pack: Package) -> Dictionary:
	var top := pack.top_item()
	if top == null:
		return {}
	var p := Sampler.peek(top, s.rng)
	s.knowledge.perceived[top.id] = p
	return p


## 从某格（含手上）最上面那个已拆开的箱里拿出最上面那包，抱到手上。返回 {ok, reason, package}。
func take_pack_from_box(slot_id: String) -> Dictionary:
	var sl := _slot(slot_id)
	var h := carrier()
	if sl == null or sl.packages.is_empty() or not sl.packages[-1].is_box():
		return {"ok": false, "reason": "最上面不是箱子"}
	var box: Package = sl.packages[-1]
	if box.sealed:
		return {"ok": false, "reason": "箱子还封着，先拆箱"}
	if box.packs.is_empty():
		return {"ok": false, "reason": "箱子空了"}
	if h.stack.height() > 0 and not h.mixes():
		return {"ok": false, "reason": "手上拿着散货，先放下"}
	var pack: Package = box.packs[-1]
	# 箱子在手上时，拿出一包后手上是"空箱 + 一包"，超了；这种情况先把箱子放下
	if sl.id == h.id or not h.can_hold(pack):
		return {"ok": false, "reason": "手上抱不下了"}
	box.packs.pop_back()
	h.packages.append(pack)
	return {"ok": true, "package": pack}


## 把一包放回某格最上面那个已拆开的箱里。
func put_pack_into_box(slot_id: String) -> Dictionary:
	var sl := _slot(slot_id)
	var h := carrier()
	if sl == null or sl.packages.is_empty() or not sl.packages[-1].is_box() or sl.packages[-1].sealed:
		return {"ok": false, "reason": "这里没有打开的箱子"}
	if h.packages.is_empty() or h.packages[-1].is_box():
		return {"ok": false, "reason": "手上没有包"}
	var box: Package = sl.packages[-1]
	if box.packs.size() >= Wholesale.BOX_PACKS:
		return {"ok": false, "reason": "箱子装满了"}
	box.packs.append(h.packages.pop_back())
	return {"ok": true}


## 拆包上架（07 §2）：src 格（可以是手上）最上面那包撕开，按袋里的顺序倒到 dst 那堆顶上，
## 放不下的留在开口包里（开口包还是一个包）；倒空了包就没了。返回 {ok, reason, moved, left}。
func unpack_to(src_slot: String, dst_slot: String) -> Dictionary:
	var a := _slot(src_slot)
	var b := _slot(dst_slot)
	if a == null or a.packages.is_empty() or a.packages[-1].is_box():
		return {"ok": false, "reason": "最上面不是包", "moved": 0, "left": 0}
	if b == null or b.stack.max_height <= 0 or not b.packages.is_empty():
		return {"ok": false, "reason": "这里放不了散货", "moved": 0, "left": 0}
	var pack: Package = a.packages[-1]
	pack.sealed = false
	var moved := 0
	while not pack.items.is_empty() and not b.stack.is_full():
		var it: ScarfItem = pack.items.pop_front()
		place_on_top(it, b.id)
		moved += 1
	if pack.items.is_empty():
		a.packages.pop_back()
	s.bus.emit("pack_unpacked", {"package_id": pack.id, "moved": moved})
	return {"ok": moved > 0, "reason": "" if moved > 0 else "那堆满了", "moved": moved, "left": pack.items.size()}


## 从开口包里拿最上面那条到手上（包得是开着的，手上不能抱着别的箱包）。推车时进散货篓，车上的开口包也能拿。
func take_from_open_pack(slot_id: String) -> ScarfItem:
	var sl := _slot(slot_id)
	var h := carrier()
	if sl == null or sl.packages.is_empty() or sl.packages[-1].is_box() or sl.packages[-1].sealed:
		return null
	if h.stack.is_full() or (not h.packages.is_empty() and not h.mixes()):
		return null
	var pack: Package = sl.packages[-1]
	var it: ScarfItem = pack.items.pop_back()
	if pack.items.is_empty():
		sl.packages.pop_back()
	place_on_top(it, h.id)
	return it


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
	# 成交价比按实际值算（除掉物价 π），否则通胀会经由 C 项推高景气（09 §1.2）
	var base_price := float(DataDB.sku(item.sku_id)["base_price"]) * s.economy.price_level
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
## 店面、仓库的设备要给格子 pos，摆不下（RoomGrid.can_place）就不买。
func buy_equipment(def_id: String, location_id: String, pos := Vector2i(-1, -1)) -> Dictionary:
	var def: Dictionary = DataDB.equipment().get(def_id, {})
	if def.is_empty():
		return {"ok": false, "reason": "没有这种设备"}
	var phase: String = def.get("phase", "any")
	if phase != "any" and phase != s.player.phase:
		return {"ok": false, "reason": "当前阶段用不上"}
	if pos.x >= 0:
		var why := RoomGrid.can_place(s.inventory, location_id, def_id, pos)
		if why != "":
			return {"ok": false, "reason": why}
	var price := s.equipment_price(def_id)
	if price > s.player.cash + 0.0001:
		return {"ok": false, "reason": "现金不够"}
	s.player.cash -= price
	var eid := s.inventory.install_equipment(def_id, location_id, pos)
	s.knowledge.add_ledger(s.clock.period, "equipment", -price, def.get("name", def_id))
	s.bus.emit("equipment_bought", {"def_id": def_id, "equipment_id": eid})
	return {"ok": true, "equipment_id": eid}


## 把店面 / 仓库里的设备挪到另一格（07 §4.1）。收银台固定不动。返回 {ok, reason}。
func move_equipment(eid: String, pos: Vector2i) -> Dictionary:
	var e: Dictionary = s.inventory.equipment.get(eid, {})
	if e.is_empty() or not e.has("pos"):
		return {"ok": false, "reason": "没有这件设备"}
	if DataDB.equipment().get(e["def_id"], {}).get("fixed", false):
		return {"ok": false, "reason": "这个挪不了"}
	var why := RoomGrid.can_place(s.inventory, e["location_id"], e["def_id"], pos, eid)
	if why != "":
		return {"ok": false, "reason": why}
	e["pos"] = [pos.x, pos.y]
	for sl in s.inventory.equipment_slots(eid):
		sl.grid_pos = pos
	return {"ok": true}


## 卖掉一件设备：上面得先清空，按 resale_ratio 退钱。返回 {ok, reason, refund}。
func sell_equipment(eid: String) -> Dictionary:
	var e: Dictionary = s.inventory.equipment.get(eid, {})
	if e.is_empty():
		return {"ok": false, "reason": "没有这件设备"}
	var def: Dictionary = DataDB.equipment().get(e["def_id"], {})
	if def.get("fixed", false):
		return {"ok": false, "reason": "这个卖不了"}
	if not s.inventory.remove_equipment(eid):
		return {"ok": false, "reason": "上面还有货，先清空"}
	var refund := s.equipment_price(e["def_id"]) * float(def.get("resale_ratio", 0.0))
	s.player.cash += refund
	s.knowledge.add_ledger(s.clock.period, "equipment", refund, "卖掉" + def.get("name", e["def_id"]))
	return {"ok": true, "refund": refund}
