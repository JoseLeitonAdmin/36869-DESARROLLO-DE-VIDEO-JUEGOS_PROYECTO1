class_name DoorInteractable
extends Area2D

@export_file("*.tscn") var target_map: String = ""
@export var target_spawn: String = "Default"
@export var prompt_text: String = "[E] Entrar"

var _player_inside: bool = false
var _prompt_label: Label = null
var _transitioning: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_create_prompt_label()


func _create_prompt_label() -> void:
	_prompt_label = Label.new()
	_prompt_label.text = prompt_text
	_prompt_label.z_index = 20
	_prompt_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(-90.0, -34.0)
	_prompt_label.size = Vector2(360.0, 24.0)
	_prompt_label.scale = Vector2(0.5, 0.5)

	var settings := LabelSettings.new()
	settings.font_size = 14
	settings.font_color = Color(1.0, 0.94, 0.72, 1.0)
	settings.outline_size = 4
	settings.outline_color = Color(0.05, 0.05, 0.08, 0.95)
	_prompt_label.label_settings = settings
	_prompt_label.visible = false
	add_child(_prompt_label)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside or _transitioning:
		return
	if _is_interact_event(event):
		get_viewport().set_input_as_handled()
		_trigger_door()


func _is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			return key_ev.keycode == KEY_E or key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_SPACE
	return false


func _trigger_door() -> void:
	if target_map.is_empty():
		return
	_transitioning = true
	MapTransition.next_spawn_point = target_spawn
	get_tree().call_deferred("change_scene_to_file", target_map)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Pastor":
		_player_inside = true
		if _prompt_label != null:
			_prompt_label.text = prompt_text
			_prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Pastor":
		_player_inside = false
		if _prompt_label != null:
			_prompt_label.visible = false
