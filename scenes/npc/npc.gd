class_name NPC
extends CharacterBody2D

@export var npc_name: String = "Aldeano"
@export var greeting_text: String = "¡Hola, Pastor!"
@export var move_speed: float = 44.0
@export var wait_time: float = 2.0
@export var loop_route: bool = true
@export var patrol_waypoints: PackedVector2Array = PackedVector2Array()

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var info_label: Label = get_node_or_null("InfoLabel")

var _current_wp_index: int = 0
var _direction_step: int = 1
var _wait_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("npcs")
	_last_position = global_position

	# Si no se asignaron waypoints por array pero existen nodos Marker2D hijos en "Route", los recolectamos
	var route_node := get_node_or_null("Route")
	if patrol_waypoints.is_empty() and route_node != null:
		var pts := PackedVector2Array()
		for child in route_node.get_children():
			if child is Node2D:
				pts.append((child as Node2D).global_position)
		patrol_waypoints = pts

	if info_label != null:
		info_label.text = npc_name
		info_label.visible = true

	_play_anim(&"idle")


func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		var is_stealth: bool = player.has_method("is_stealth_active") and player.is_stealth_active()
		var detect_radius: float = 12.0 if is_stealth else 28.0
		var dist_to_player := global_position.distance_to(player.global_position)
		if dist_to_player < detect_radius:
			velocity = Vector2.ZERO
			_face_position(player.global_position)
			_play_anim(&"idle")
			if info_label != null:
				info_label.text = npc_name + "\n\"" + greeting_text + "\""
			return
		elif info_label != null and info_label.text != npc_name:
			info_label.text = npc_name

	if patrol_waypoints.size() < 2:
		velocity = Vector2.ZERO
		_play_anim(&"idle")
		return

	if _wait_timer > 0.0:
		_wait_timer -= delta
		velocity = Vector2.ZERO
		_play_anim(&"idle")
		return

	var target: Vector2 = patrol_waypoints[_current_wp_index]
	var to_target: Vector2 = target - global_position
	var dist: float = to_target.length()

	if dist <= 4.0:
		global_position = target
		velocity = Vector2.ZERO
		_play_anim(&"idle")
		_wait_timer = wait_time
		_advance_waypoint()
		_stuck_timer = 0.0
		return

	var move_dir: Vector2 = to_target / dist
	velocity = move_dir * move_speed
	_face_direction(move_dir)
	_play_anim(&"walk")
	move_and_slide()

	# Protección contra atascos si colisiona con algún obstáculo
	if global_position.distance_to(_last_position) < 0.25:
		_stuck_timer += delta
		if _stuck_timer >= 1.5:
			_stuck_timer = 0.0
			_wait_timer = wait_time * 0.5
			_advance_waypoint()
	else:
		_stuck_timer = 0.0
	_last_position = global_position


func _advance_waypoint() -> void:
	if patrol_waypoints.size() < 2:
		return
	if loop_route:
		_current_wp_index = (_current_wp_index + 1) % patrol_waypoints.size()
	else:
		var next_idx := _current_wp_index + _direction_step
		if next_idx >= patrol_waypoints.size() or next_idx < 0:
			_direction_step = -_direction_step
			next_idx = _current_wp_index + _direction_step
		_current_wp_index = clampi(next_idx, 0, patrol_waypoints.size() - 1)


func _face_direction(dir: Vector2) -> void:
	if animated_sprite == null:
		return
	if dir.x < -0.05:
		animated_sprite.flip_h = true
	elif dir.x > 0.05:
		animated_sprite.flip_h = false


func _face_position(pos: Vector2) -> void:
	if animated_sprite == null:
		return
	var dx := pos.x - global_position.x
	if absf(dx) > 2.0:
		animated_sprite.flip_h = dx < 0.0


func _play_anim(anim_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
			animated_sprite.play(anim_name)
