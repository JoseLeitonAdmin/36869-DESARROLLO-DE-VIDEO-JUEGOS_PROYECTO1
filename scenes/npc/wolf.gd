class_name Wolf
extends CharacterBody2D

@export var move_speed: float = 52.0
@export var light_attract_stealth_speed: float = 48.0
@export var stealth_chase_speed: float = 60.0
@export var aggressive_chase_speed: float = 132.0
@export var retreat_speed: float = 104.0

@export var stealth_attack_zone_radius: float = 88.0
@export var normal_attack_zone_radius: float = 168.0
@export var light_attraction_radius: float = 210.0
@export var bite_reach: float = 20.0

@export var lantern_repel_distance: float = 135.0
@export var lantern_repel_cone_dot: float = 0.35
@export var blind_spot_offset_distance: float = 28.0
@export var post_attack_retreat_duration: float = 2.6

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
	STALK_STEALTH,
	ATTRACTED_BY_LIGHT,
	CHASE_DIRECT,
	RETREAT,
}

var _state: State = State.REST_AT_SPOT
var _rest_spot: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _retreat_dir: Vector2 = Vector2.UP
var _state_timer: float = 2.0
var _remaining_steps: int = 0
var _stuck_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _attack_cooldown: float = 0.0
var _post_attack_retreat: bool = false
var _flank_side: float = 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("wolf")
	_rng.randomize()
	_flank_side = 1.0 if _rng.randf() >= 0.5 else -1.0

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
	_play_anim(&"idle", 1.0)


func _physics_process(delta: float) -> void:
	if _is_dialog_or_menu_active():
		velocity = Vector2.ZERO
		_play_anim(&"idle", 1.0)
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	var player := get_tree().get_first_node_in_group("player") as Node2D
	_update_combat_state(player)

	match _state:
		State.RETREAT:
			_process_retreat(delta)

		State.CHASE_DIRECT:
			_process_direct_chase(delta, player)

		State.ATTRACTED_BY_LIGHT:
			_process_light_attraction(delta, player)

		State.STALK_STEALTH:
			_process_stealth_stalk(delta, player)

		State.REST_AT_SPOT:
			velocity = Vector2.ZERO
			_play_anim(&"idle", 1.0)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_remaining_steps = _rng.randi_range(min_wander_steps, max_wander_steps)
				_pick_random_wander_target()

		State.WANDER_PAUSE:
			velocity = Vector2.ZERO
			_play_anim(&"idle", 1.0)
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


func _is_dialog_or_menu_active() -> bool:
	var dialogic_node := get_node_or_null("/root/Dialogic")
	if dialogic_node != null and dialogic_node.get("current_timeline") != null:
		return true
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("is_menu_open") and player.is_menu_open():
		return true
	return false


func _update_combat_state(player: Node2D) -> void:
	if player == null:
		if _state in [State.STALK_STEALTH, State.ATTRACTED_BY_LIGHT, State.CHASE_DIRECT, State.RETREAT]:
			_start_return_to_rest_spot()
		return

	# Si se está alejando tras el primer ataque, mantiene la retirada hasta terminar
	if _state == State.RETREAT:
		return

	if _attack_cooldown > 0.0:
		return

	var is_stealth: bool = player.has_method("is_stealth_active") and player.is_stealth_active()
	var dist_to_player := global_position.distance_to(player.global_position)
	var zone_radius := get_current_attack_zone_radius(is_stealth)
	var attracted_by_light := is_attracted_by_player_light(player)

	if not is_stealth:
		# Sin sigilo: si entra en la zona amplia o lo atrae la luz, va mucho más rápido y ataca de inmediato
		if dist_to_player <= zone_radius or attracted_by_light:
			_state = State.CHASE_DIRECT
		elif _state in [State.STALK_STEALTH, State.ATTRACTED_BY_LIGHT, State.CHASE_DIRECT]:
			_start_return_to_rest_spot()
	else:
		# Agachado (en sigilo):
		# - Si alumbra / tiene la luz encendida cerca, la luz atrae al lobo pero no muy rápido
		# - Si está a oscuras dentro de la zona de ataque reducida, lo persigue buscando sus puntos ciegos
		if is_illuminated_by_player(player) or (attracted_by_light and dist_to_player <= light_attraction_radius):
			_state = State.ATTRACTED_BY_LIGHT
		elif dist_to_player <= zone_radius:
			_state = State.STALK_STEALTH
		elif _state in [State.STALK_STEALTH, State.ATTRACTED_BY_LIGHT, State.CHASE_DIRECT]:
			_start_return_to_rest_spot()


func get_current_attack_zone_radius(is_stealth: bool) -> float:
	return stealth_attack_zone_radius if is_stealth else normal_attack_zone_radius


func is_player_lantern_on(player: Node2D) -> bool:
	if player == null:
		return false
	if GameState.has_lighter and GameState.lighter_on:
		return true
	var lantern_node := player.get_node_or_null("LanternLight") as PointLight2D
	return lantern_node != null and lantern_node.enabled


func is_attracted_by_player_light(player: Node2D) -> bool:
	if not is_player_lantern_on(player):
		return false
	var dist := global_position.distance_to(player.global_position)
	return dist <= light_attraction_radius


func is_illuminated_by_player(player: Node2D) -> bool:
	if not is_player_lantern_on(player):
		return false

	var to_wolf := global_position - player.global_position
	var dist := to_wolf.length()
	if dist > lantern_repel_distance:
		return false
	if dist <= 14.0:
		return true

	var look_dir := _get_player_look_direction(player)
	var forward_dot := (to_wolf / dist).dot(look_dir)
	return forward_dot >= lantern_repel_cone_dot


func _get_player_look_direction(player: Node2D) -> Vector2:
	if player != null and player.has_method("get_lantern_aim_angle"):
		var aim_angle := float(player.call("get_lantern_aim_angle"))
		return Vector2.RIGHT.rotated(aim_angle)
	return Vector2.DOWN


func get_blind_spot_target(player: Node2D) -> Vector2:
	if player == null:
		return global_position

	var look_dir := _get_player_look_direction(player)
	var to_wolf := global_position - player.global_position
	var dist := to_wolf.length()

	var rear_blind_spot := player.global_position - look_dir * blind_spot_offset_distance
	if dist <= 0.001:
		return rear_blind_spot

	var dir_from_player := to_wolf / dist
	var forward_dot := dir_from_player.dot(look_dir)

	if forward_dot <= -0.25:
		if dist <= blind_spot_offset_distance * 1.15:
			return player.global_position
		return rear_blind_spot

	var perp := Vector2(-look_dir.y, look_dir.x)
	var side_dot := dir_from_player.dot(perp)
	var side_sign := _flank_side if absf(side_dot) < 0.15 else signf(side_dot)
	return rear_blind_spot + perp * side_sign * (blind_spot_offset_distance * 0.85)


func _process_light_attraction(_delta: float, player: Node2D) -> void:
	if player == null:
		_start_return_to_rest_spot()
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist <= bite_reach:
		_perform_attack(player, true)
		return

	# Atraído por la luz mientras el jugador está agachado: avanza hacia la luz pero no muy rápido
	var move_dir := to_player / maxf(dist, 0.001)
	velocity = move_dir * light_attract_stealth_speed
	_face_direction(move_dir)
	_play_anim(&"walk", 0.92)
	move_and_slide()
	_last_pos = global_position

	if global_position.distance_to(player.global_position) <= bite_reach:
		_perform_attack(player, true)


func _process_stealth_stalk(delta: float, player: Node2D) -> void:
	if player == null:
		_start_return_to_rest_spot()
		return

	var dist_to_player := global_position.distance_to(player.global_position)
	if dist_to_player <= bite_reach:
		_perform_attack(player, true)
		return

	var blind_target := get_blind_spot_target(player)
	var to_target := blind_target - global_position
	var move_dir := to_target.normalized() if to_target.length_squared() > 1.0 else (player.global_position - global_position).normalized()

	velocity = move_dir * stealth_chase_speed
	_face_direction(move_dir)
	_play_anim(&"walk", 1.05)
	move_and_slide()

	if get_slide_collision_count() > 0 or global_position.distance_to(_last_pos) < 0.15:
		_stuck_timer += delta
		if _stuck_timer >= 0.35:
			_stuck_timer = 0.0
			_flank_side = -_flank_side
	else:
		_stuck_timer = 0.0
	_last_pos = global_position

	if global_position.distance_to(player.global_position) <= bite_reach:
		_perform_attack(player, true)


func _process_direct_chase(_delta: float, player: Node2D) -> void:
	if player == null:
		_start_return_to_rest_spot()
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist <= bite_reach:
		_perform_attack(player, false)
		return

	var move_dir := to_player / maxf(dist, 0.001)
	velocity = move_dir * aggressive_chase_speed
	_face_direction(move_dir)
	_play_anim(&"walk", 1.5)
	move_and_slide()
	_last_pos = global_position

	if global_position.distance_to(player.global_position) <= bite_reach:
		_perform_attack(player, false)


func _perform_attack(player: Node2D, was_stealth: bool) -> void:
	_face_direction((player.global_position - global_position).normalized())
	GameState.lose_sheep(1)
	if GameState.sheep_count > 0 and player.has_method("show_story_message"):
		if was_stealth:
			player.show_story_message(
				"¡El Lobo te alcanzó en la penumbra!",
				"El Lobo Feroz te atacó y se aleja entre las sombras. Ovejas restantes: " + str(GameState.sheep_count)
			)
		else:
			player.show_story_message(
				"¡El Lobo te escuchó y atacó!",
				"Caminabas sin sigilo y el Lobo se abalanzó de inmediato antes de alejarse. Ovejas restantes: " + str(GameState.sheep_count)
			)
	# Después del primer ataque se aleja de inmediato
	_start_retreat(player)


func _start_retreat(player: Node2D) -> void:
	_post_attack_retreat = true
	_state = State.RETREAT
	_state_timer = post_attack_retreat_duration
	_attack_cooldown = post_attack_retreat_duration + 1.4

	if player == null:
		_retreat_dir = (_rest_spot - global_position).normalized()
	else:
		var away := global_position - player.global_position
		_retreat_dir = away.normalized() if away.length_squared() > 1.0 else -_get_player_look_direction(player)


func _process_retreat(delta: float) -> void:
	_state_timer -= delta
	velocity = _retreat_dir * retreat_speed
	_face_direction(_retreat_dir)
	_play_anim(&"walk", 1.35)
	move_and_slide()

	if get_slide_collision_count() > 0 or global_position.distance_to(_last_pos) < 0.15:
		_stuck_timer += delta
		if _stuck_timer >= 0.3:
			_stuck_timer = 0.0
			_flank_side = -_flank_side
			_retreat_dir = _retreat_dir.rotated(PI * 0.45 * _flank_side)
	else:
		_stuck_timer = 0.0
	_last_pos = global_position

	if _state_timer <= 0.0:
		_post_attack_retreat = false
		_start_return_to_rest_spot()


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
	_play_anim(&"walk", 1.0)
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
	_play_anim(&"idle", 1.0)
	_state = State.WANDER_PAUSE
	_state_timer = step_pause_time


func _start_return_to_rest_spot() -> void:
	_target_pos = _rest_spot
	_stuck_timer = 0.0
	_state = State.RETURN_TO_SPOT


func _arrive_at_rest_spot() -> void:
	velocity = Vector2.ZERO
	_play_anim(&"idle", 1.0)
	_state = State.REST_AT_SPOT
	_state_timer = rest_spot_wait_time


func _face_direction(dir: Vector2) -> void:
	if animated_sprite == null:
		return
	if dir.x < -0.05:
		animated_sprite.flip_h = false
	elif dir.x > 0.05:
		animated_sprite.flip_h = true


func _play_anim(anim_name: StringName, speed_mult: float = 1.0) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	animated_sprite.speed_scale = speed_mult
	if animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
			animated_sprite.play(anim_name)


func get_rest_spot() -> Vector2:
	return _rest_spot


func is_resting_at_spot() -> bool:
	return _state == State.REST_AT_SPOT


func get_state() -> State:
	return _state
