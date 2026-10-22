class_name GameState
extends RefCounted
## 存档根：一局游戏的全部状态。to_dict / from_dict 只做结构转换，迁移由 SaveManager 负责。

const GAME_VERSION := "0.0.1"

var clock := Clock.new()
var rng := GameRng.new()
var flags := DifficultyFlags.new()
var player := PlayerState.new():
	set(v):
		player = v
		if inventory != null:
			inventory.player = v
var inventory := Inventory.new():
	set(v):
		inventory = v
		if inventory != null:
			inventory.player = player
var knowledge := Knowledge.new()
var economy := EconomyState.new()
var trend := TrendState.new()
var customers := CustomerRegistry.new()
var street := Street.new()
## 摆摊状态：{x: 摊位位置或 null, prices: {sku_id: 标价}}
var stall: Dictionary = {"x": null, "prices": {}}
## 本旬本地进货店目录
var supplier_catalog: Array = []
## 本旬统计（旬末结算用）
var period_stats: Dictionary = {}
## 剧情 / 随机事件预留（01 §4.8）
var events: Dictionary = {}
var meta: Dictionary = {}
## 运行时：事件总线（不存档）
var bus := EventBus.new()


func _init() -> void:
	# 手上能拿多少看玩家的【搬运】（Inventory.hand()）
	inventory.player = player


static func new_game(seed_value: int) -> GameState:
	var s := GameState.new()
	s.rng = GameRng.new(seed_value)
	s.meta = {"seed": str(seed_value), "created_with": GAME_VERSION}
	s.inventory.add_location("player", "Carry")
	s.inventory.add_location("stall", "Stall", 2.0)
	s.inventory.install_equipment("bag_basic", "player")
	s.inventory.install_equipment("stall_cloth", "stall")
	s.trend = TrendState.create(s.rng)
	s.reset_period_stats()
	return s


func econ_now() -> Dictionary:
	return economy.effective(clock.period)


## 默认标价：表里的 base_price 是实际值，乘当前物价水平 π 取整（09 §1.2）。
func list_price(sku_id: String) -> float:
	return snappedf(float(DataDB.sku(sku_id)["base_price"]) * economy.price_level, 1.0)


## 设备表价也是实际值，买卖时乘 π（01 §4.9、09 §7）。
func equipment_price(def_id: String) -> float:
	return snappedf(float(DataDB.equipment().get(def_id, {}).get("price", 0.0)) * economy.price_level, 1.0)


func trend_now() -> Dictionary:
	return trend.effective(clock.period)


## 阶段门 / 前置用的世界标记（02 §7.2）。
func world_flags() -> Dictionary:
	return {"shop_opened": player.phase == "shop", "has_employee": false, "has_vehicle": false}


func reset_period_stats() -> void:
	period_stats = {"traffic": 0, "stayed": 0, "sales": 0, "revenue": 0.0, "cost_of_goods": 0.0,
		"price_ratio_sum": 0.0, "purchases": 0.0, "collapses": 0, "xp_earned": 0.0, "ignored": 0,
		"no_match": 0, "scared_off": 0, "lost_after_deal": 0}


func to_dict() -> Dictionary:
	return {
		"schema_version": SaveManager.CURRENT_SCHEMA_VERSION,
		"game_version": GAME_VERSION,
		"meta": meta.duplicate(true),
		"clock": clock.to_dict(),
		"rng": rng.to_dict(),
		"flags": flags.to_dict(),
		"player": player.to_dict(),
		"inventory": inventory.to_dict(),
		"knowledge": knowledge.to_dict(),
		"economy": economy.to_dict(),
		"trend": trend.to_dict(),
		"customers": customers.to_dict(),
		"street": street.to_dict(),
		"stall": stall.duplicate(true),
		"supplier_catalog": supplier_catalog.duplicate(true),
		"period_stats": period_stats.duplicate(true),
		"events": events.duplicate(true),
	}


## 只接受已迁移到当前版本的字典。
static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.meta = d.get("meta", {})
	s.clock = Clock.from_dict(d.get("clock", {}))
	s.rng = GameRng.from_dict(d.get("rng", {}))
	s.flags = DifficultyFlags.from_dict(d.get("flags", {}))
	s.player = PlayerState.from_dict(d.get("player", {}))
	s.inventory = Inventory.from_dict(d.get("inventory", {}))
	s.knowledge = Knowledge.from_dict(d.get("knowledge", {}))
	s.economy = EconomyState.from_dict(d.get("economy", {}))
	s.trend = TrendState.from_dict(d.get("trend", {}))
	s.customers = CustomerRegistry.from_dict(d.get("customers", {}))
	s.street = Street.from_dict(d.get("street", {}))
	s.stall = d.get("stall", {"x": null, "prices": {}})
	s.supplier_catalog = d.get("supplier_catalog", [])
	s.reset_period_stats()
	var ps: Dictionary = d.get("period_stats", {})
	for k in ps:
		s.period_stats[k] = ps[k]
	s.events = d.get("events", {})
	return s
