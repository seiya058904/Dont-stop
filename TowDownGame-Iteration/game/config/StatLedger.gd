extends RefCounted
var rows: Array = []
func add(stat: String, kind: String, id: String, title: String, operation: String, value, active = true, condition = ""):
	rows.append({"stat_id":stat,"source_type":kind,"source_id":id,"source_name":title,"operation":operation,"value":value,"active":active,"condition":condition,"sequence":rows.size()})
func ordered(stat: String) -> Array:
	var order={"base":0,"level":1,"legacy":2,"upgrade":3,"talent":4,"reward":5,"condition":6,"rule":7,"history":8}
	var result=rows.filter(func(r): return r.stat_id==stat)
	result.sort_custom(func(a,b): return a.sequence<b.sequence if a.source_type==b.source_type else order.get(a.source_type,9)<order.get(b.source_type,9))
	return result
static func text(row: Dictionary) -> String:
	var value=str(row.value)
	if row.value is float or row.value is int:
		match row.operation:
			"percentage_point": value="%+.1fpp" % (float(row.value)*100)
			"additive_percentage": value="%+.1f%%（同组相加）" % (float(row.value)*100)
			"multiplier": value="×%.3f" % float(row.value)
			"flat": value="%+.3f" % float(row.value)
	return row.source_name+" · "+value+(" · 生效" if row.active else " · 未生效")+(" · "+row.condition if not row.condition.is_empty() else "")
