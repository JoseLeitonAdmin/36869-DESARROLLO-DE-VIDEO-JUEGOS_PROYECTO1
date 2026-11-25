extends Node

const SAVE_PATH: String = "user://savegame.cfg"

signal lighter_collected
signal lighter_toggled(is_on: bool)
signal sheep_changed(new_count: int)
signal inventory_changed
signal quest_status_changed(new_status: int)
signal game_saved

enum QuestStatus {
	NOT_STARTED = 0,
	ACCEPTED = 1,
	ITEM_FOUND = 2,
	COMPLETED = 3,
}

const QUEST_ITEM_ID: String = "reloj_engranaje"
const QUEST_ITEM_NAME: String = "Engranaje del Reloj"
const QUEST_ITEM_ICON: String = "res://assets/structures/clock_face.png"

var max_sheep: int = 4
var sheep_count: int = 4
var current_night: int = 1
var has_lighter: bool = false
var lighter_on: bool = false
var village_quest_status: int = QuestStatus.NOT_STARTED
var inventory: Array[Dictionary] = []
var last_saved_map: String = ""
var last_saved_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	DialogicResourceUtil.update_directory("dch")
	DialogicResourceUtil.update_directory("dtl")
	var dialogic_node := get_node_or_null("/root/Dialogic")
	if dialogic_node != null and dialogic_node.has_signal("signal_event"):
		if not dialogic_node.is_connected("signal_event", _on_dialogic_signal_event):
			dialogic_node.connect("signal_event", _on_dialogic_signal_event)


func _on_dialogic_signal_event(argument: Variant) -> void:
	var action := str(argument).strip_edges()
	match action:
		"accept_quest":
			accept_village_quest()
		"deliver_quest":
			deliver_quest_item()
		"restore_sheep":
			restore_sheep(1)


func collect_lighter() -> void:
	if not has_lighter:
		has_lighter = true
		lighter_collected.emit()
	add_item("lighter", "Lámpara [F]", "res://assets/player/Lighter.png")


func accept_village_quest() -> void:
	if village_quest_status == QuestStatus.NOT_STARTED:
		if has_item(QUEST_ITEM_ID):
			village_quest_status = QuestStatus.ITEM_FOUND
		else:
			village_quest_status = QuestStatus.ACCEPTED
		quest_status_changed.emit(village_quest_status)


func collect_quest_item() -> void:
	add_item(QUEST_ITEM_ID, QUEST_ITEM_NAME, QUEST_ITEM_ICON)
	if village_quest_status < QuestStatus.COMPLETED:
		village_quest_status = QuestStatus.ITEM_FOUND
		quest_status_changed.emit(village_quest_status)


func deliver_quest_item() -> void:
	remove_item(QUEST_ITEM_ID)
	if village_quest_status != QuestStatus.COMPLETED:
		village_quest_status = QuestStatus.COMPLETED
		if sheep_count < max_sheep:
			restore_sheep(1)
		quest_status_changed.emit(village_quest_status)


func add_item(item_id: String, item_name: String, icon_path: String) -> void:
	for item in inventory:
		if item.get("id", "") == item_id:
			return
	inventory.append({
		"id": item_id,
		"name": item_name,
		"icon": icon_path,
	})
	inventory_changed.emit()


func remove_item(item_id: String) -> bool:
	for i in range(inventory.size()):
		if inventory[i].get("id", "") == item_id:
			inventory.remove_at(i)
			inventory_changed.emit()
			return true
	return false


func has_item(item_id: String) -> bool:
	for item in inventory:
		if item.get("id", "") == item_id:
			return true
	return false


func set_sheep_count(new_count: int) -> void:
	var clamped := clampi(new_count, 0, max_sheep)
	if sheep_count == clamped:
		return
	sheep_count = clamped
	sheep_changed.emit(sheep_count)


func lose_sheep(amount: int = 1) -> void:
	set_sheep_count(sheep_count - amount)


func restore_sheep(amount: int = 1) -> void:
	set_sheep_count(sheep_count + amount)


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


func save_game(map_path: String = "", player_pos: Vector2 = Vector2.ZERO) -> bool:
	var cfg := ConfigFile.new()
	if not map_path.is_empty():
		last_saved_map = map_path
	if player_pos != Vector2.ZERO:
		last_saved_pos = player_pos

	cfg.set_value("game", "sheep_count", sheep_count)
	cfg.set_value("game", "max_sheep", max_sheep)
	cfg.set_value("game", "current_night", current_night)
	cfg.set_value("game", "has_lighter", has_lighter)
	cfg.set_value("game", "lighter_on", lighter_on)
	cfg.set_value("game", "village_quest_status", village_quest_status)
	cfg.set_value("game", "inventory", inventory.duplicate(true))
	cfg.set_value("game", "time_of_day", int(TimeManager.current_time))
	cfg.set_value("game", "map_path", last_saved_map)
	cfg.set_value("game", "player_x", last_saved_pos.x)
	cfg.set_value("game", "player_y", last_saved_pos.y)

	var err := cfg.save(SAVE_PATH)
	if err == OK:
		game_saved.emit()
		return true
	return false


func has_save_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	if not has_save_game():
		return false
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false

	max_sheep = int(cfg.get_value("game", "max_sheep", 4))
	sheep_count = clampi(int(cfg.get_value("game", "sheep_count", 4)), 0, max_sheep)
	current_night = int(cfg.get_value("game", "current_night", 1))
	has_lighter = bool(cfg.get_value("game", "has_lighter", false))
	lighter_on = bool(cfg.get_value("game", "lighter_on", false)) and has_lighter
	village_quest_status = clampi(int(cfg.get_value("game", "village_quest_status", QuestStatus.NOT_STARTED)), 0, 3)

	inventory.clear()
	var saved_inv: Variant = cfg.get_value("game", "inventory", [])
	if saved_inv is Array:
		for entry in saved_inv:
			if entry is Dictionary:
				inventory.append(entry)

	if has_lighter and not has_item("lighter"):
		inventory.append({
			"id": "lighter",
			"name": "Lámpara [F]",
			"icon": "res://assets/player/Lighter.png",
		})

	var saved_time := int(cfg.get_value("game", "time_of_day", int(TimeManager.TimeOfDay.DAY)))
	TimeManager.set_time(clampi(saved_time, 0, 2) as TimeManager.TimeOfDay)

	last_saved_map = str(cfg.get_value("game", "map_path", ""))
	last_saved_pos = Vector2(
		float(cfg.get_value("game", "player_x", 0.0)),
		float(cfg.get_value("game", "player_y", 0.0))
	)

	sheep_changed.emit(sheep_count)
	inventory_changed.emit()
	quest_status_changed.emit(village_quest_status)
	if has_lighter:
		lighter_collected.emit()
	lighter_toggled.emit(lighter_on)
	return true


func reset_state() -> void:
	sheep_count = max_sheep
	current_night = 1
	has_lighter = false
	lighter_on = false
	village_quest_status = QuestStatus.NOT_STARTED
	inventory.clear()
	sheep_changed.emit(sheep_count)
	inventory_changed.emit()
	quest_status_changed.emit(village_quest_status)
	lighter_toggled.emit(false)
