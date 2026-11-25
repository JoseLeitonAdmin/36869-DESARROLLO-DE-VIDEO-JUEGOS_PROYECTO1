class_name QuestItemPickup
extends Area2D

@export var item_title: String = "Engranaje del Reloj"
@export var bob_amplitude: float = 1.6
@export var bob_speed: float = 3.0

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var glow_light: PointLight2D = get_node_or_null("GlowLight")

var _player_inside: bool = false
var _prompt_label: Label = null
var _base_sprite_y: float = 0.0
var _base_light_energy: float = 0.8
var _time_accum: float = 0.0
var _collected: bool = false


func _ready() -> void:
	if GameState.village_quest_status >= GameState.QuestStatus.ITEM_FOUND or GameState.has_item(GameState.QUEST_ITEM_ID):
		queue_free()
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not GameState.quest_status_changed.is_connected(_on_quest_status_changed):
		GameState.quest_status_changed.connect(_on_quest_status_changed)

	_create_prompt_label()

	if sprite != null:
		_base_sprite_y = sprite.position.y
	if glow_light != null:
		_base_light_energy = glow_light.energy


func _exit_tree() -> void:
	if GameState.quest_status_changed.is_connected(_on_quest_status_changed):
		GameState.quest_status_changed.disconnect(_on_quest_status_changed)


func _process(delta: float) -> void:
	_time_accum += delta
	if sprite != null:
		sprite.position.y = _base_sprite_y + sin(_time_accum * bob_speed) * bob_amplitude
	if glow_light != null:
		glow_light.energy = _base_light_energy + sin(_time_accum * 4.5) * 0.14


func _create_prompt_label() -> void:
	_prompt_label = Label.new()
	_prompt_label.text = _get_current_prompt_text()
	_prompt_label.z_index = 20
	_prompt_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(-105.0, -32.0)
	_prompt_label.size = Vector2(420.0, 24.0)
	_prompt_label.scale = Vector2(0.5, 0.5)

	var settings := LabelSettings.new()
	settings.font_size = 14
	settings.font_color = Color(1.0, 0.90, 0.58, 1.0)
	settings.outline_size = 4
	settings.outline_color = Color(0.05, 0.05, 0.08, 0.95)
	_prompt_label.label_settings = settings
	_prompt_label.visible = false
	add_child(_prompt_label)


func _get_current_prompt_text() -> String:
	if GameState.village_quest_status == GameState.QuestStatus.ACCEPTED:
		return "[E] Recoger " + item_title
	return "[E] Examinar objeto perdido"


func _on_quest_status_changed(_new_status: int) -> void:
	if GameState.village_quest_status >= GameState.QuestStatus.ITEM_FOUND:
		queue_free()
		return
	if _prompt_label != null:
		_prompt_label.text = _get_current_prompt_text()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside or _collected:
		return
	var dialogic_node := get_node_or_null("/root/Dialogic")
	if dialogic_node != null and dialogic_node.get("current_timeline") != null:
		return
	if _is_interact_event(event):
		get_viewport().set_input_as_handled()
		_interact()


func _is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			return key_ev.keycode == KEY_E or key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_SPACE
	return false


func _interact() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if GameState.village_quest_status == GameState.QuestStatus.NOT_STARTED:
		if player != null and player.has_method("show_story_message"):
			player.show_story_message(
				"Objeto Perdido en el Pueblo",
				"Un antiguo engranaje de reloj brilla entre la hierba. Quizá algún aldeano en la plaza central lo esté buscando."
			)
		return

	_collected = true
	GameState.collect_quest_item()
	if player != null and player.has_method("show_story_message"):
		player.show_story_message(
			item_title + " obtenido",
			"Has encontrado el Engranaje del Reloj que perdió Clara. Regresa a la plaza del pueblo y habla con ella para entregárselo."
		)
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Pastor":
		_player_inside = true
		if _prompt_label != null:
			_prompt_label.text = _get_current_prompt_text()
			_prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Pastor":
		_player_inside = false
		if _prompt_label != null:
			_prompt_label.visible = false
