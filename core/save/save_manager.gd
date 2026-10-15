class_name SaveManager
extends RefCounted
## 存档与版本迁移（01 §7.1，硬约束：任何版本都不能让旧存档失效）。
## - JSON 字典 + schema_version，绝不序列化 Resource。
## - 逐版本迁移链：core/save/migrations/m_XXXX_to_YYYY.gd。
## - 保留未知字段：读档时记住原始字典，写档时把新字典深合并回去。
## - 写档前旧档改名为 .bak；任何失败都不覆盖原档。

## 每次改存档结构 +1，并且：新增迁移脚本、登记到 Migrations.REGISTRY、新增 tests/save_fixtures/ 下的一份存档。
const CURRENT_SCHEMA_VERSION := 1

## 这些路径下是"集合"（以 ID 为键的字典）：条目被删除就该消失，合并时不从旧档补回。
const COLLECTION_PATHS := [
	"inventory/slots", "inventory/equipment", "inventory/locations",
	"customers/regulars", "customers/return_probability",
	"knowledge/labels", "knowledge/perceived",
	"stall/prices", "flags", "player/skills", "events",
]

## 读档时的原始（已迁移）字典，用于写回时保留未知字段。
var _raw: Dictionary = {}


## 读档。返回 {ok, state, error, migrated_from}。失败时绝不改动文件。
func load_game(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "存档不存在"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "无法读取存档"}
	var text := f.get_as_text()
	f.close()
	return load_from_string(text)


func load_from_string(text: String, migrations: Dictionary = Migrations.REGISTRY) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "存档格式损坏"}
	var r := migrate(parsed, migrations)
	if not r["ok"]:
		return r
	_raw = r["data"]
	r["state"] = GameState.from_dict(r["data"])
	return r


## 把任意旧版本字典逐级迁移到当前版本。
static func migrate(data: Dictionary, migrations: Dictionary = Migrations.REGISTRY, target: int = CURRENT_SCHEMA_VERSION) -> Dictionary:
	var v := int(data.get("schema_version", 0))
	var from_v := v
	if v > target:
		return {"ok": false, "error": "存档来自更新的游戏版本（存档版本 %d，当前支持 %d），请更新游戏" % [v, target]}
	var d: Dictionary = data.duplicate(true)
	while v < target:
		if not migrations.has(v):
			return {"ok": false, "error": "缺少从版本 %d 升级的迁移脚本" % v}
		var m = migrations[v].new()
		d = m.migrate(d)
		v += 1
		d["schema_version"] = v
	return {"ok": true, "data": d, "migrated_from": from_v}


## 写档：tmp → 旧档改名 .bak → tmp 改名为正式档。
func save_game(state: GameState, path: String) -> Dictionary:
	var out := deep_merge(_raw, state.to_dict())
	_raw = out
	var text := JSON.stringify(out, "\t")
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "无法写入 %s" % tmp}
	f.store_string(text)
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return {"ok": false, "error": "无法访问存档目录"}
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			dir.remove(bak.get_file())
		var e := dir.rename(path.get_file(), bak.get_file())
		if e != OK:
			return {"ok": false, "error": "备份旧存档失败（%d），未覆盖" % e}
	var e2 := dir.rename(tmp.get_file(), path.get_file())
	if e2 != OK:
		return {"ok": false, "error": "写入存档失败（%d），旧档保留在 .bak" % e2}
	return {"ok": true}


## 深合并：fresh 覆盖 old；old 中 fresh 没有的键保留（未知字段），集合路径除外。
static func deep_merge(old: Dictionary, fresh: Dictionary, path: String = "") -> Dictionary:
	var out: Dictionary = fresh.duplicate(true)
	if COLLECTION_PATHS.has(path):
		# 集合本身以新数据为准，但仍保留共同条目里的未知字段。
		for k in fresh:
			if old.has(k) and old[k] is Dictionary and fresh[k] is Dictionary:
				out[k] = deep_merge(old[k], fresh[k], path + "/*")
		return out
	for k in old:
		var child := str(k) if path == "" else path + "/" + str(k)
		if not fresh.has(k):
			out[k] = old[k]
		elif old[k] is Dictionary and fresh[k] is Dictionary:
			out[k] = deep_merge(old[k], fresh[k], child)
	return out
