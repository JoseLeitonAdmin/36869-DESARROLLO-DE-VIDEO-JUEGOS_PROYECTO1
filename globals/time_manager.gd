extends Node

enum TimeOfDay {
	DAY,
	AFTERNOON,
	NIGHT,
}

signal time_changed(new_time: TimeOfDay)

var current_time: TimeOfDay = TimeOfDay.DAY


func cycle_time() -> void:
	var next_idx: int = (int(current_time) + 1) % 3
	set_time(next_idx as TimeOfDay)


func set_time(new_time: TimeOfDay) -> void:
	if current_time == new_time:
		return
	current_time = new_time
	time_changed.emit(current_time)


func get_time_label(time_val: TimeOfDay = current_time) -> String:
	match time_val:
		TimeOfDay.DAY:
			return "Día"
		TimeOfDay.AFTERNOON:
			return "Tarde"
		TimeOfDay.NIGHT:
			return "Noche"
	return "Día"


func get_ambient_color(map_name: String, time_val: TimeOfDay = current_time) -> Color:
	if map_name.contains("Interior"):
		match time_val:
			TimeOfDay.DAY:
				return Color(0.96, 0.93, 0.88, 1.0)
			TimeOfDay.AFTERNOON:
				return Color(0.84, 0.70, 0.58, 1.0)
			TimeOfDay.NIGHT:
				return Color(0.42, 0.44, 0.58, 1.0)
	elif map_name.contains("Guarida"):
		match time_val:
			TimeOfDay.DAY:
				return Color(0.82, 0.86, 0.90, 1.0)
			TimeOfDay.AFTERNOON:
				return Color(0.70, 0.55, 0.60, 1.0)
			TimeOfDay.NIGHT:
				return Color(0.24, 0.27, 0.44, 1.0)
	else:
		# Exteriores: Granja y Pueblo Rural
		match time_val:
			TimeOfDay.DAY:
				return Color(1.0, 1.0, 0.98, 1.0)
			TimeOfDay.AFTERNOON:
				return Color(0.94, 0.68, 0.48, 1.0)
			TimeOfDay.NIGHT:
				return Color(0.24, 0.29, 0.48, 1.0)
	return Color(1.0, 1.0, 1.0, 1.0)


func get_accent_color(time_val: TimeOfDay = current_time) -> Color:
	match time_val:
		TimeOfDay.DAY:
			return Color(0.98, 0.84, 0.36, 1.0)
		TimeOfDay.AFTERNOON:
			return Color(0.96, 0.58, 0.30, 1.0)
		TimeOfDay.NIGHT:
			return Color(0.56, 0.74, 1.0, 1.0)
	return Color(0.98, 0.84, 0.36, 1.0)
