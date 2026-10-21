extends Control
## 旬末结算（01 §3）：本旬收支、客流、预报。只看过去，不看未来。


func _ready() -> void:
	UIKit.background(self)
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	add_child(center)
	var p := UIKit.panel(UIKit.PANEL, 24)
	center.add_child(p)
	var v := UIKit.vbox(10)
	p.add_child(v)
	var r := Game.last_report
	v.add_child(UIKit.label("%s · 结算" % r.get("label", ""), 26, UIKit.ACCENT))
	if r.get("sold_out", false):
		v.add_child(UIKit.label("卖光！货全卖完，提前收摊了。", 20, UIKit.GOOD))
	var profit := float(r.get("revenue", 0.0)) - float(r.get("purchases", 0.0))
	for line in [
		"路过摊位的人：%d　停下来看的：%d　成交：%d 件" % [r.get("traffic", 0), r.get("stayed", 0), r.get("sales", 0)],
		"没顾上理会就走掉的：%d　没找到想要的：%d" % [r.get("ignored", 0), r.get("no_match", 0)],
		"被价格吓跑的：%d　谈成没拿到货：%d" % [r.get("scared_off", 0), r.get("lost_after_deal", 0)],
		"营业额：%.1f 元　本旬进货：%.1f 元　进出相抵：%+.1f 元" % [r.get("revenue", 0.0), r.get("purchases", 0.0), profit],
		"货堆倒塌：%d 次　收摊时行囊装不下丢掉：%d 件" % [r.get("collapses", 0), r.get("lost_on_pack_up", 0)],
		"获得经验：%.0f" % r.get("xp_earned", 0.0),
		"现金：%.1f 元" % Game.state.player.cash,
	]:
		v.add_child(UIKit.label(line, 18))
	if r.get("season_changed", false):
		v.add_child(UIKit.label("换季了：现在是%s天，大家想要的材质在变。" % Clock.SEASON_NAMES[Game.state.clock.season()], 18, UIKit.GOOD))
	for f in r.get("forecasts", []):
		v.add_child(UIKit.label("审美积累：" + f["text"], 18, UIKit.GOOD))
	v.add_child(UIKit.label("已自动存档。", 14, UIKit.MUTED))
	v.add_child(UIKit.button("进入下一旬", func(): Game.goto("planning"), 20))
