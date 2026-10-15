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


func skill_level(skill_id: String) -> int:
	return int(skills.get(skill_id, {}).get("level", 0))


func to_dict() -> Dictionary:
	return {
		"cash": cash, "xp_pool": xp_pool, "skills": skills.duplicate(true), "phase": phase,
		"reputation": reputation, "shop_opened_period": shop_opened_period,
		"loans": loans.duplicate(true), "available": available,
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
	return p
