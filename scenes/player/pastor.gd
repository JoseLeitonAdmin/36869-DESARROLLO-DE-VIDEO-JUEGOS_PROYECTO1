class_name Pastor
extends CharacterBody2D

@export var walk_speed: float = 110.0
@export var sprint_speed: float = 165.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = get_node_or_null("Camera2D")


func _ready() -> void:
	add_to_group("player")
	_apply_transition_spawn()
	_configure_camera_limits()
	if animated_sprite and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation(&"idle"):
			animated_sprite.play(&"idle")


func _physics_process(_delta: float) -> void:
	var input_dir := _get_movement_input()
	var current_speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed

	if input_dir != Vector2.ZERO:
		velocity = input_dir * current_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, current_speed)

	move_and_slide()
	_update_animation(input_dir)


func _get_movement_input() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	return dir.normalized()


func _update_animation(dir: Vector2) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	if dir.x < -0.05:
		animated_sprite.flip_h = true
	elif dir.x > 0.05:
		animated_sprite.flip_h = false

	if dir.length_squared() > 0.01:
		if animated_sprite.sprite_frames.has_animation(&"run"):
			if animated_sprite.animation != &"run":
				animated_sprite.play(&"run")
	else:
		if animated_sprite.sprite_frames.has_animation(&"idle"):
			if animated_sprite.animation != &"idle":
				animated_sprite.play(&"idle")


func _apply_transition_spawn() -> void:
	if MapTransition.next_spawn_point.is_empty():
		return
	var map_root := get_parent()
	if map_root == null:
		return
	var spawn_node := map_root.get_node_or_null("SpawnPoints/" + MapTransition.next_spawn_point) as Node2D
	if spawn_node != null:
		global_position = spawn_node.global_position
		if camera != null:
			camera.reset_smoothing()
	MapTransition.next_spawn_point = ""


func _configure_camera_limits() -> void:
	if camera == null:
		return
	var map_root := get_parent()
	if map_root == null:
		return
	var ground_layer := map_root.get_node_or_null("GroundLayer") as TileMapLayer
	if ground_layer == null or ground_layer.tile_set == null:
		return
	var used_rect: Rect2i = ground_layer.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return
	var tile_size: Vector2i = ground_layer.tile_set.tile_size
	camera.limit_left = used_rect.position.x * tile_size.x
	camera.limit_top = used_rect.position.y * tile_size.y
	camera.limit_right = used_rect.end.x * tile_size.x
	camera.limit_bottom = used_rect.end.y * tile_size.y
	camera.reset_smoothing()
