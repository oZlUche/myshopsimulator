class_name SkillSystem
extends RefCounted
## 共用经验池 + 玩家分配（02 §1）、阶段门（§7.1）、前置（§7.2）。
## 效果查询集中在这里，所有效果都是认知层 / 采样参数，不直接改真相层。


static func def(skill_id: String) -> Dictionary:
	return DataDB.skills().get(skill_id, {})


static func max_level(skill_id: String) -> int:
	return def(skill_id).get("xp_costs", []).size()


static func cost_of(skill_id: String, level: int) -> float:
	var costs: Array = def(skill_id).get("xp_costs", [])
	return float(costs[level - 1]) if level >= 1 and level <= costs.size() else INF


## 下一级是否可投入；返回 "" 表示可以，否则返回原因。
static func lock_reason(player: PlayerState, skill_id: String, flags: Dictionary) -> String:
	var d := def(skill_id)
	if d.is_empty():
		return "未知技能"
	var next := player.skill_level(skill_id) + 1
	if next > max_level(skill_id):
		return "已满级"
	var phases: Array = d.get("phases", [])
	if not phases.is_empty() and not phases.has(player.phase):
		return "当前阶段不可用"
	var cap := int(d.get("phase_cap", {}).get(player.phase, max_level(skill_id)))
	if next > cap:
		return "开店后解锁" if player.phase == "stall" else "已达上限"
	for req in d.get("requires", {}).get(str(next), []):
		if not _req_met(player, req, flags):
			return _req_text(req)
	return ""


static func _req_met(player: PlayerState, req: Dictionary, flags: Dictionary) -> bool:
	if req.has("any"):
		for r in req["any"]:
			if _req_met(player, r, flags):
				return true
		return false
	if req.has("flag"):
		return bool(flags.get(req["flag"], false))
	return player.skill_level(req["skill"]) >= int(req["level"])


static func _req_text(req: Dictionary) -> String:
	if req.has("any"):
		return "需要：" + " 或 ".join(req["any"].map(func(r): return _req_text(r).trim_prefix("需要：")))
	if req.has("flag"):
		return "需要：" + {"shop_opened": "已开店", "has_employee": "雇有员工", "has_vehicle": "拥有车辆"}.get(req["flag"], req["flag"])
	return "需要：%s Lv%d" % [def(req["skill"]).get("name", req["skill"]), int(req["level"])]


## 从经验池向某技能下一级节点投入经验；达到阈值自动点亮（溢出留在节点外不浪费）。
## 返回实际投入量。
static func invest(player: PlayerState, skill_id: String, amount: float, flags: Dictionary) -> float:
	if lock_reason(player, skill_id, flags) != "":
		return 0.0
	var rec: Dictionary = player.skills.get(skill_id, {"level": 0, "invested": 0.0})
	var need := cost_of(skill_id, int(rec["level"]) + 1) - float(rec["invested"])
	var put := minf(minf(amount, player.xp_pool), need)
	if put <= 0.0:
		return 0.0
	player.xp_pool -= put
	rec["invested"] = float(rec["invested"]) + put
	if rec["invested"] >= cost_of(skill_id, int(rec["level"]) + 1) - 0.0001:
		rec["level"] = int(rec["level"]) + 1
		rec["invested"] = 0.0
	player.skills[skill_id] = rec
	return put


# ---- 效果查询（数值待阶段 0 实测调整） ----

## 强化记忆：记住最近 N 次操作的槽位（02 §2.2）。
static func memory_slots(player: PlayerState) -> int:
	return [0, 1, 1, 3, 3, 10, 20][clampi(player.skill_level("memory"), 0, 6)]


## 数学能手决定的全局 precision 上限（02 §2.5）。
static func precision_cap(player: PlayerState) -> int:
	var m := player.skill_level("math")
	return 2 if m >= 6 else (1 if m >= 3 else 0)


## 吆喝（02 §2.8）。只在摆摊阶段生效。
static func shout_mods(player: PlayerState) -> Dictionary:
	var lv := player.skill_level("shout") if player.phase == "stall" else 0
	return {
		"area_radius": 2 + (1 if lv >= 1 else 0) + (1 if lv >= 5 else 0),
		"stay_mult": 1.3 if lv >= 2 else 1.0,
		"intent_add": 0.1 if lv >= 3 else 0.0,
		"reserve_mult": 1.06 if lv >= 4 else 1.0,
	}


## 口才（02 §2.6 → 06 §3.4）→ HaggleState 修正。
## Lv1/Lv3 提高策略成功率（随等级 +0.08）；Lv2 策略失败少扣 P；Lv4 挑选容差 +0.1；Lv5 每第三次出手不扣耐心；Lv6 回购。
static func haggle_mods(player: PlayerState) -> Dictionary:
	var lv := player.skill_level("eloquence")
	var shout := shout_mods(player)
	return {
		"eloquence": lv,
		"fail_penalty": 0.03 if lv >= 2 else 0.05,
		"tol_add": 0.1 if lv >= 4 else 0.0,
		"free_every": 3 if lv >= 5 else 0,
		"reserve_mult": shout["reserve_mult"],
		"loyalty_bonus": 0.05 if lv >= 6 else 0.0,
	}
