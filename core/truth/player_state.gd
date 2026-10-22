class_name PlayerState
extends RefCounted
## 玩家：现金、经验池、技能、阶段。信誉在开店前为 null（01 §4.5）。

var cash: float = 500.0
## 共用经验池中尚未分配的部分（02 §1）
var xp_pool: float = 0.0
## {skill_id: {"level": int, "invested": float}}；invested 为投入下一级节点的经验
var skills: Dictionary = {}
## "stall" / "shop"
var phase: String = "stall"
var reputation: Variant = null
var shop_opened_period: Variant = null
var loans: Array = []
var available: bool = true
## 手推车（07 §2.1）：推着走时车就是「手上」；停着时停在 cart_room 的 cart_cell，车头朝 cart_facing。
## cart_room 为空 = 还没停进哪间屋（老存档、刚开店），进屋时停在门口附近。
var pushing_cart: bool = false
var cart_room: String = ""
var cart_cell: Vector2i = Vector2i(-1, -1)
var cart_facing: String = "sw"


func skill_level(skill_id: String) -> int:
	return int(skills.get(skill_id, {}).get("level", 0))


func to_dict() -> Dictionary:
	return {
		"cash": cash, "xp_pool": xp_pool, "skills": skills.duplicate(true), "phase": phase,
		"reputation": reputation, "shop_opened_period": shop_opened_period,
		"loans": loans.duplicate(true), "available": available,
		"pushing_cart": pushing_cart, "cart_room": cart_room, "cart_cell": [cart_cell.x, cart_cell.y], "cart_facing": cart_facing,
	}


static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.cash = float(d.get("cash", 500.0))
	p.xp_pool = float(d.get("xp_pool", 0.0))
	var sk: Dictionary = d.get("skills", {})
	for id in sk:
		p.skills[id] = {"level": int(sk[id].get("level", 0)), "invested": float(sk[id].get("invested", 0.0))}
	p.phase = str(d.get("phase", "stall"))
	p.reputation = d.get("reputation", null)
	p.shop_opened_period = d.get("shop_opened_period", null)
	p.loans = d.get("loans", [])
	p.available = bool(d.get("available", true))
	p.pushing_cart = bool(d.get("pushing_cart", false))
	p.cart_room = str(d.get("cart_room", ""))
	var cc: Array = d.get("cart_cell", [-1, -1])
	p.cart_cell = Vector2i(int(cc[0]), int(cc[1]))
	p.cart_facing = str(d.get("cart_facing", "sw"))
	return p
