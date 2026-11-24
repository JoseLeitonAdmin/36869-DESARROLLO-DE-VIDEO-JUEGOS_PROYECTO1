extends Node

signal lighter_collected
signal lighter_toggled(is_on: bool)

var has_lighter: bool = false
var lighter_on: bool = false


func collect_lighter() -> void:
	if has_lighter:
		return
	has_lighter = true
	lighter_collected.emit()


func set_lighter_on(active: bool) -> void:
	if not has_lighter:
		active = false
	if lighter_on == active:
		return
	lighter_on = active
	lighter_toggled.emit(lighter_on)


func toggle_lighter() -> bool:
	if not has_lighter:
		return false
	set_lighter_on(not lighter_on)
	return true


func reset_state() -> void:
	has_lighter = false
	lighter_on = false
	lighter_toggled.emit(false)
