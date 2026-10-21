class_name Package
extends RefCounted
## 真相层：整箱、整包（07 §1）。箱是纸箱，装若干包，外面只有物流单；包是塑料袋，装同一款的若干条，
## 隔着袋子看得到最上面那条，袋上贴着厂家的货号贴纸（写的是款：图案 + 材质）。
## 放在槽位的 packages 里（下标 0 在最下面）；箱里的包、包里的围巾同样是下标 0 在最下面。

## 占地（07 §2）：一箱 = 3 个单位，一包 = 1 个单位；槽位按 pkg_capacity 限制能放多少。
const UNITS := {"box": 3, "pack": 1}

var id: String
## "box" | "pack"
var kind: String = "pack"
## 箱：胶带还封着；包：袋子还没撕。
var sealed: bool = true
## 包：里面的围巾（下标 0 在袋底）
var items: Array[ScarfItem] = []
## 箱：里面的包（下标 0 在箱底）
var packs: Array[Package] = []
## 箱外的物流单 {sender, piece, of, weight}（真相层，但谁都看得到）
var waybill: Dictionary = {}
## 包上的货号贴纸：款 {pattern, material}。基础玩法总是对的，品质开关开启后可能贴错（05）。
var sticker: Dictionary = {}
## 包：单色 single / 混色 mixed（07 §1.1）
var mix: String = "single"
var provenance: Dictionary = {}


func units() -> int:
	return int(UNITS.get(kind, 1))


func is_box() -> bool:
	return kind == "box"


func is_empty() -> bool:
	return items.is_empty() if kind == "pack" else packs.is_empty()


func top_item() -> ScarfItem:
	return null if items.is_empty() else items[-1]


func top_pack() -> Package:
	return null if packs.is_empty() else packs[-1]


## 箱或包里一共几条。
func item_count() -> int:
	if kind == "pack":
		return items.size()
	var n := 0
	for p in packs:
		n += p.items.size()
	return n


## 里面所有的围巾（箱就展开到每包里）。
func all_items() -> Array[ScarfItem]:
	if kind == "pack":
		return items.duplicate()
	var out: Array[ScarfItem] = []
	for p in packs:
		out.append_array(p.items)
	return out


func to_dict() -> Dictionary:
	var d := {"id": id, "kind": kind, "sealed": sealed, "provenance": provenance.duplicate(true)}
	if kind == "pack":
		d["items"] = items.map(func(i): return i.to_dict())
		d["sticker"] = sticker.duplicate()
		d["mix"] = mix
	else:
		d["packs"] = packs.map(func(p): return p.to_dict())
		d["waybill"] = waybill.duplicate()
	return d


static func from_dict(d: Dictionary) -> Package:
	var p := Package.new()
	p.id = str(d.get("id", ""))
	p.kind = str(d.get("kind", "pack"))
	p.sealed = bool(d.get("sealed", true))
	p.provenance = d.get("provenance", {})
	for x in d.get("items", []):
		p.items.append(ScarfItem.from_dict(x))
	for x in d.get("packs", []):
		p.packs.append(Package.from_dict(x))
	p.waybill = d.get("waybill", {})
	p.sticker = d.get("sticker", {})
	p.mix = str(d.get("mix", "single"))
	return p
