extends RefCounted
# Temporary instrumentation only, injected by tools/profile-m6.py.
static var totals = {}
static var stack: Array = []
var label: String
var started: int
var children = 0
func _init(key: String):
	label = key
	started = Time.get_ticks_usec()
	stack.append(weakref(self))
func _notification(what):
	if what != NOTIFICATION_PREDELETE: return
	var elapsed = Time.get_ticks_usec()-started
	stack.pop_back()
	if not stack.is_empty():
		var parent = stack.back().get_ref()
		if parent: parent.children += elapsed
	var row = totals.get(label,{"calls":0,"inclusive_us":0,"self_us":0,"max_us":0})
	row.calls += 1; row.inclusive_us += elapsed; row.self_us += elapsed-children; row.max_us = maxi(row.max_us,elapsed)
	totals[label] = row
static func report():
	print("M6 PROFILE ",JSON.stringify(totals))
