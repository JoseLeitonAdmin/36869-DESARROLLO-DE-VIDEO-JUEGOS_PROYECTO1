class_name Wolf
extends CharacterBody2D

@export var move_speed: float = 52.0
@export var wander_radius: float = 72.0
@export var min_wander_steps: int = 2
@export var max_wander_steps: int = 4
@export var step_pause_time: float = 1.1
@export var rest_spot_wait_time: float = 4.5
@export var use_custom_rest_spot: bool = false
@export var custom_rest_spot: Vector2 = Vector2.ZERO

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

enum State {
	WANDER_MOVE,
	WANDER_PAUSE,
	RETURN_TO_SPOT,
	REST_AT_SPOT,
}

var _state: State = State.REST_AT_SPOT
var _rest_spot: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _state_timer: float = 2.0
var _remaining_steps: int = 0
var _stuck_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _attack_cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("wolf")
	_rng.randomize()

	var spot_marker := get_node_or_null("RestSpot") as Node2D
	if use_custom_rest_spot:
		_rest_spot = custom_rest_spot
	elif spot_marker != null:
		_rest_spot = spot_marker.global_position
	else:
		_rest_spot = global_position

	_target_pos = _rest_spot
	_last_pos = global_position
	_state = State.REST_AT_SPOT
	_state_timer = 1.5
	_play_anim(&"idle")


func _physics_process(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	_check_player_proximity()

	match _state:
		State.REST_AT_SPOT:
			velocity = Vector2.ZERO
			_play_anim(&"idle")
			_state_timer -= delta
			if _state_timer <= 0.0:
				_remaining_steps = _rng.randi_range(min_wander_steps, max_wander_steps)
				_pick_random_wander_target()

		State.WANDER_PAUSE:
			velocity = Vector2.ZERO
			_play_anim(&"idle")
			_state_timer -= delta
			if _state_timer <= 0.0:
				if _remaining_steps > 0:
					_pick_random_wander_target()
				else:
					_start_return_to_rest_spot()

		State.WANDER_MOVE:
			_move_towards_target(delta, false)

		State.RETURN_TO_SPOT:
			_move_towards_target(delta, true)


func _move_towards_target(delta: float, returning_to_spot: bool) -> void:
	var to_target := _target_pos - global_position
	var dist := to_target.length()
	if dist <= 4.0:
		if returning_to_spot:
			global_position = _rest_spot
			_arrive_at_rest_spot()
		else:
			_arrive_at_wander_step()
		return

	var dir := to_target / dist
	velocity = dir * move_speed
	_face_direction(dir)
	_play_anim(&"walk")
	move_and_slide()

	if get_slide_collision_count() > 0 or global_position.distance_to(_last_pos) < 0.2:
		_stuck_timer += delta
		if _stuck_timer >= 0.45:
			_stuck_timer = 0.0
			if returning_to_spot:
				_arrive_at_rest_spot()
			else:
				_arrive_at_wander_step()
	else:
		_stuck_timer = 0.0
	_last_pos = global_position


func _pick_random_wander_target() -> void:
	_remaining_steps -= 1
	var angle := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(24.0, wander_radius)
	_target_pos = _rest_spot + Vector2(cos(angle), sin(angle)) * dist
	_stuck_timer = 0.0
	_state = State.WANDER_MOVE


func _arrive_at_wander_step() -> void:
	velocity = Vector2.ZERO
	_play_anim(&"idle")
	_state = State.WANDER_PAUSE
	_state_timer = step_pause_time


func _start_return_to_rest_spot() -> void:
	_target_pos = _rest_spot
	_stuck_timer = 0.0
	_state = State.RETURN_TO_SPOT


func _arrive_at_rest_spot() -> void:
	velocity = Vector2.ZERO
	_play_anim(&"idle")
	_state = State.REST_AT_SPOT
	_state_timer = rest_spot_wait_time


func _check_player_proximity() -> void:
	if _attack_cooldown > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var is_stealth: bool = player.has_method("is_stealth_active") and player.is_stealth_active()
	var catch_radius: float = 13.0 if is_stealth else 24.0
	if global_position.distance_to(player.global_position) <= catch_radius:
		_attack_cooldown = 3.5
		_face_direction((player.global_position - global_position).normalized())
		GameState.lose_sheep(1)
		if player.has_method("show_story_message"):
			player.show_story_message(
				"¡El Lobo te ha descubierto!",
				"El Lobo Feroz ataca tu rebaño en las sombras. Ovejas restantes: " + str(GameState.sheep_count)
			)


func _face_direction(dir: Vector2) -> void:
	if animated_sprite == null:
		return
	# Los sprites del lobo miran hacia la izquierda por defecto
	if dir.x < -0.05:
		animated_sprite.flip_h = false
	elif dir.x > 0.05:
		animated_sprite.flip_h = true


func _play_anim(anim_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
			animated_sprite.play(anim_name)


func get_rest_spot() -> Vector2:
	return _rest_spot


func is_resting_at_spot() -> bool:
	return _state == State.REST_AT_SPOT
