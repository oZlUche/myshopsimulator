extends TestCase


## 人站在货架斜对角那格时（远近一样），不管排序前谁在前，人都要画在货架后面一笔。
func test_person_drawn_after_equipment_on_depth_tie() -> void:
	var rack := {"d": 2.0, "kind": "equip"}
	var person := {"d": 2.0, "kind": "person"}
	var pile := {"d": 2.0, "kind": "pile"}
	for order in [[rack, person, pile], [person, rack, pile], [person, pile, rack]]:
		var things: Array = order.duplicate()
		things.sort_custom(RoomView._draw_before)
		assert_eq(things[-1]["kind"], "person")
	var far := {"d": 1.0, "kind": "person"}
	var things: Array = [rack, far]
	things.sort_custom(RoomView._draw_before)
	assert_eq(things[0]["kind"], "person", "远的人仍然先画")
