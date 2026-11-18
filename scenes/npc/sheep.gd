class_name Sheep
extends CharacterBody2D

@export var wander_speed: float = 22.0
@export var wander_radius: float = 42.0
@export var min_wait_time: float = 1.5
@export var max_wait_time: float = 4.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var bleat_label: Label = get_node_or_null("BleatLabel")

var _home_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _is_walking: bool = false
var _state_timer: float = 1.0
var _bleat_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("sheep")
	_rng.randomize()
	_home_pos = global_position
	_target_pos = _home_pos
	_state_timer = _rng.randf_range(0.5, max_wait_time)
	if bleat_label != null:
		bleat_label.visible = false
	_play_anim(&"idle")


func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and global_position.distance_to(player.global_position) < 26.0:
		if _bleat_timer <= 0.0 and bleat_label != null:
			bleat_label.visible = true
			_bleat_timer = 2.2
	if _bleat_timer > 0.0:
		_bleat_timer -= delta
		if _bleat_timer <= 0.0 and bleat_label != null:
			bleat_label.visible = false

	if _is_walking:
		var to_target := _target_pos - global_position
		if to_target.length() <= 3.0:
			_stop_and_graze()
			return
		var dir := to_target.normalized()
		velocity = dir * wander_speed
		if animated_sprite != null and absf(dir.x) > 0.05:
			animated_sprite.flip_h = dir.x < 0.0
		_play_anim(&"walk")
		move_and_slide()
		if get_slide_collision_count() > 0:
			_stop_and_graze()
	else:
		velocity = Vector2.ZERO
		_play_anim(&"idle")
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_new_target()


func _stop_and_graze() -> void:
	_is_walking = false
	velocity = Vector2.ZERO
	_state_timer = _rng.randf_range(min_wait_time, max_wait_time)
	_play_anim(&"idle")


func _pick_new_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(12.0, wander_radius)
	_target_pos = _home_pos + Vector2(cos(angle), sin(angle)) * dist
	_is_walking = true


func _play_anim(anim_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
			animated_sprite.play(anim_name)
