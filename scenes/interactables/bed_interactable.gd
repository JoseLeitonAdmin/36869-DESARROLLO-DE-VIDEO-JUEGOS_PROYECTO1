class_name BedInteractable
extends Area2D

@export var prompt_text: String = "[E] Descansar / Guardar"

var _player_inside: bool = false
var _prompt_label: Label = null


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
	_prompt_label.position = Vector2(-90.0, -32.0)
	_prompt_label.size = Vector2(360.0, 24.0)
	_prompt_label.scale = Vector2(0.5, 0.5)

	var settings := LabelSettings.new()
	settings.font_size = 14
	settings.font_color = Color(1.0, 0.92, 0.64, 1.0)
	settings.outline_size = 4
	settings.outline_color = Color(0.05, 0.05, 0.08, 0.95)
	_prompt_label.label_settings = settings
	_prompt_label.visible = false
	add_child(_prompt_label)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside:
		return
	if _is_interact_event(event):
		var player := get_tree().get_first_node_in_group("player")
		if player != null and player.has_method("open_bed_save_menu"):
			get_viewport().set_input_as_handled()
			player.open_bed_save_menu()


func _is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			return key_ev.keycode == KEY_E or key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_SPACE
	return false


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
