class_name Pastor
extends CharacterBody2D

const TIME_ICONS_TEX: Texture2D = preload("res://assets/effects/time_icons.png")
const LIGHTER_TEX: Texture2D = preload("res://assets/player/Lighter.png")

@export var walk_speed: float = 110.0
@export var sprint_speed: float = 165.0
@export var stealth_speed: float = 62.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var held_lantern: Sprite2D = get_node_or_null("HeldLantern")
@onready var camera: Camera2D = get_node_or_null("Camera2D")
@onready var lantern: PointLight2D = get_node_or_null("LanternLight")

var _hud_layer: CanvasLayer = null
var _zone_label: Label = null
var _time_button: Button = null
var _time_icon_tex: AtlasTexture = null
var _time_btn_style: StyleBoxFlat = null
var _time_btn_hover_style: StyleBoxFlat = null
var _lighter_icon_rect: TextureRect = null
var _lighter_status_label: Label = null
var _stealth_status_label: Label = null
var _dialog_panel: PanelContainer = null
var _dialog_title: Label = null
var _dialog_body: Label = null
var _dialog_timer: float = 0.0
var _time_tween: Tween = null

var _facing_dir: String = "down"
var _facing_left: bool = false
var _is_stealth: bool = false
var _base_lantern_energy: float = 1.35
var _lantern_flicker_time: float = 0.0


func _ready() -> void:
	add_to_group("player")
	if lantern != null:
		_base_lantern_energy = lantern.energy

	_apply_transition_spawn()
	_configure_camera_limits()
	_cache_map_lights()
	_build_hud()

	if not TimeManager.time_changed.is_connected(_on_time_changed):
		TimeManager.time_changed.connect(_on_time_changed)
	if not GameState.lighter_collected.is_connected(_on_lighter_state_changed):
		GameState.lighter_collected.connect(_on_lighter_state_changed)
	if not GameState.lighter_toggled.is_connected(_on_lighter_toggled):
		GameState.lighter_toggled.connect(_on_lighter_toggled)

	_apply_time_of_day(TimeManager.current_time, true)
	_sync_lantern_visual()
	_apply_stealth_visual()
	_update_animation(Vector2.ZERO, false)


func _exit_tree() -> void:
	if TimeManager.time_changed.is_connected(_on_time_changed):
		TimeManager.time_changed.disconnect(_on_time_changed)
	if GameState.lighter_collected.is_connected(_on_lighter_state_changed):
		GameState.lighter_collected.disconnect(_on_lighter_state_changed)
	if GameState.lighter_toggled.is_connected(_on_lighter_toggled):
		GameState.lighter_toggled.disconnect(_on_lighter_toggled)


func _process(delta: float) -> void:
	if _dialog_panel != null and _dialog_panel.visible and _dialog_timer > 0.0:
		_dialog_timer -= delta
		if _dialog_timer <= 0.0:
			_dialog_panel.visible = false

	if lantern != null and lantern.enabled:
		_lantern_flicker_time += delta
		lantern.energy = _base_lantern_energy + sin(_lantern_flicker_time * 9.0) * 0.06 + sin(_lantern_flicker_time * 17.3) * 0.03
		_update_held_lantern_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			if key_ev.keycode == KEY_F:
				_toggle_lantern()
			elif key_ev.keycode == KEY_C:
				_toggle_stealth()
			elif _dialog_panel != null and _dialog_panel.visible and (key_ev.keycode == KEY_ESCAPE or key_ev.keycode == KEY_E or key_ev.keycode == KEY_SPACE):
				_dialog_panel.visible = false
				get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	var input_dir := _get_movement_input()
	var is_sprinting := not _is_stealth and Input.is_key_pressed(KEY_SHIFT)
	var current_speed := stealth_speed if _is_stealth else (sprint_speed if is_sprinting else walk_speed)

	if input_dir != Vector2.ZERO:
		velocity = input_dir * current_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, current_speed)

	move_and_slide()
	_update_animation(input_dir, is_sprinting)


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


func _update_animation(dir: Vector2, is_sprinting: bool) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var is_moving := dir.length_squared() > 0.01
	if is_moving:
		var ax := absf(dir.x)
		var ay := absf(dir.y)
		if ax > ay + 0.05:
			_facing_dir = "side"
			_facing_left = dir.x < 0.0
		elif ay > ax + 0.05:
			_facing_dir = "up" if dir.y < 0.0 else "down"
			_facing_left = false
		elif _facing_dir == "side":
			_facing_left = dir.x < 0.0
		else:
			_facing_dir = "up" if dir.y < 0.0 else "down"

	var anim_name: StringName
	if _is_stealth:
		anim_name = StringName(("stealth_" if is_moving else "stealth_idle_") + _facing_dir)
		animated_sprite.speed_scale = 1.0
	else:
		anim_name = StringName(("walk_" if is_moving else "idle_") + _facing_dir)
		animated_sprite.speed_scale = 1.4 if (is_moving and is_sprinting) else 1.0

	animated_sprite.flip_h = (_facing_dir == "side") and _facing_left

	if animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
			animated_sprite.play(anim_name)

	_update_held_lantern_transform()


func _update_held_lantern_transform() -> void:
	var hand_pos := Vector2(5.5, -6.0)
	var hand_z := 1
	var crouch_offset := 1.6 if _is_stealth else 0.0

	match _facing_dir:
		"down":
			hand_pos = Vector2(5.5, -6.0 + crouch_offset)
			hand_z = 1
		"up":
			hand_pos = Vector2(5.5, -6.8 + crouch_offset)
			hand_z = 0
		"side":
			var side_x := -5.5 if _facing_left else 5.5
			hand_pos = Vector2(side_x, -6.0 + crouch_offset)
			hand_z = 1

	if velocity.length_squared() > 4.0:
		hand_pos.y += sin(_lantern_flicker_time * 11.0) * 0.5

	if held_lantern != null:
		held_lantern.position = hand_pos
		held_lantern.z_index = hand_z
		held_lantern.flip_h = (_facing_dir == "side") and _facing_left

	if lantern != null:
		lantern.position = hand_pos + Vector2(0.0, 1.4)


func is_stealth_active() -> bool:
	return _is_stealth


func get_stealth_detection_multiplier() -> float:
	return 0.45 if _is_stealth else 1.0


func show_story_message(title_text: String, body_text: String) -> void:
	if _dialog_panel == null:
		return
	_dialog_title.text = title_text
	_dialog_body.text = body_text
	_dialog_panel.visible = true
	_dialog_timer = 7.0


func _toggle_stealth() -> void:
	_is_stealth = not _is_stealth
	_apply_stealth_visual()
	_update_animation(_get_movement_input(), false)


func _apply_stealth_visual() -> void:
	if animated_sprite != null:
		animated_sprite.modulate = Color(0.84, 0.88, 0.98, 0.90) if _is_stealth else Color(1.0, 1.0, 1.0, 1.0)
	_refresh_status_hud()


func _toggle_lantern() -> void:
	if not GameState.has_lighter:
		show_story_message("Sin encendedor", "Aún no tienes el encendedor. Búscalo sobre la mesa dentro de tu cabaña.")
		return
	GameState.toggle_lighter()


func _on_lighter_state_changed() -> void:
	_sync_lantern_visual()


func _on_lighter_toggled(_is_on: bool) -> void:
	_sync_lantern_visual()


func _sync_lantern_visual() -> void:
	var active := GameState.has_lighter and GameState.lighter_on
	if held_lantern != null:
		held_lantern.visible = active
	if lantern != null:
		lantern.enabled = active
		if active:
			lantern.energy = _base_lantern_energy
	_update_held_lantern_transform()
	_refresh_status_hud()


func _refresh_status_hud() -> void:
	if _lighter_status_label != null and _lighter_icon_rect != null:
		if not GameState.has_lighter:
			_lighter_icon_rect.modulate = Color(0.55, 0.55, 0.55, 0.45)
			_lighter_status_label.text = "Encendedor: Busca en la cabaña"
			_lighter_status_label.add_theme_color_override("font_color", Color(0.66, 0.70, 0.76, 0.85))
		elif GameState.lighter_on:
			_lighter_icon_rect.modulate = Color(1.0, 0.96, 0.82, 1.0)
			_lighter_status_label.text = "Encendedor: Encendido [F]"
			_lighter_status_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42, 1.0))
		else:
			_lighter_icon_rect.modulate = Color(0.92, 0.92, 0.92, 0.92)
			_lighter_status_label.text = "Encendedor: Apagado [F]"
			_lighter_status_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.82, 0.95))

	if _stealth_status_label != null:
		if _is_stealth:
			_stealth_status_label.text = "Sigilo: ACTIVO [C]"
			_stealth_status_label.add_theme_color_override("font_color", Color(0.54, 0.88, 1.0, 1.0))
		else:
			_stealth_status_label.text = "Sigilo: Inactivo [C]"
			_stealth_status_label.add_theme_color_override("font_color", Color(0.66, 0.70, 0.76, 0.80))


func _on_time_button_pressed() -> void:
	TimeManager.cycle_time()


func _on_time_changed(new_time: TimeManager.TimeOfDay) -> void:
	if not is_inside_tree():
		return
	_apply_time_of_day(new_time, false)


func _cache_map_lights() -> void:
	var map_root := get_parent()
	if map_root == null:
		return
	var lights_node := map_root.get_node_or_null("Lights")
	if lights_node == null:
		return
	for child in lights_node.get_children():
		if child is PointLight2D:
			var pl := child as PointLight2D
			if not pl.has_meta("base_energy"):
				pl.set_meta("base_energy", pl.energy)
			if not pl.has_meta("base_color"):
				pl.set_meta("base_color", pl.color)


func _apply_time_of_day(time_val: TimeManager.TimeOfDay, instant: bool) -> void:
	_update_time_button_visuals(time_val)

	var map_root := get_parent()
	if map_root == null:
		return
	var map_name := map_root.name

	_sync_lantern_visual()

	var target_ambient := TimeManager.get_ambient_color(map_name, time_val)
	var ambient_node := map_root.get_node_or_null("AmbientTint") as CanvasModulate

	if _time_tween != null and _time_tween.is_valid():
		_time_tween.kill()

	var lights_node := map_root.get_node_or_null("Lights")

	if instant:
		if ambient_node != null:
			ambient_node.color = target_ambient
		if lights_node != null:
			for child in lights_node.get_children():
				if child is PointLight2D:
					var pl := child as PointLight2D
					var target_cfg := _get_light_target_config(pl, map_name, time_val)
					pl.color = target_cfg["color"]
					pl.energy = target_cfg["energy"]
					pl.enabled = pl.energy > 0.01
		return

	_time_tween = create_tween()
	_time_tween.set_parallel(true)
	_time_tween.set_trans(Tween.TRANS_SINE)
	_time_tween.set_ease(Tween.EASE_IN_OUT)

	if ambient_node != null:
		_time_tween.tween_property(ambient_node, "color", target_ambient, 0.45)

	if lights_node != null:
		for child in lights_node.get_children():
			if child is PointLight2D:
				var pl := child as PointLight2D
				var target_cfg := _get_light_target_config(pl, map_name, time_val)
				var target_e: float = target_cfg["energy"]
				var target_c: Color = target_cfg["color"]
				if target_e > 0.01:
					pl.enabled = true
				_time_tween.tween_property(pl, "energy", target_e, 0.45)
				_time_tween.tween_property(pl, "color", target_c, 0.45)

	_time_tween.chain().tween_callback(_finalize_disabled_lights)


func _finalize_disabled_lights() -> void:
	var map_root := get_parent()
	if map_root == null:
		return
	var lights_node := map_root.get_node_or_null("Lights")
	if lights_node == null:
		return
	for child in lights_node.get_children():
		if child is PointLight2D:
			var pl := child as PointLight2D
			if pl.energy <= 0.01:
				pl.enabled = false


func _get_light_target_config(pl: PointLight2D, map_name: String, time_val: TimeManager.TimeOfDay) -> Dictionary:
	var base_e: float = float(pl.get_meta("base_energy", pl.energy))
	var base_c: Color = pl.get_meta("base_color", pl.color) as Color
	var lname := pl.name

	if map_name.contains("Interior"):
		if lname.begins_with("WindowLight"):
			match time_val:
				TimeManager.TimeOfDay.DAY:
					return {"energy": base_e * 1.35, "color": Color(0.95, 0.96, 1.0, 1.0)}
				TimeManager.TimeOfDay.AFTERNOON:
					return {"energy": base_e * 1.10, "color": Color(1.0, 0.72, 0.42, 1.0)}
				TimeManager.TimeOfDay.NIGHT:
					return {"energy": base_e * 0.45, "color": Color(0.45, 0.56, 0.95, 1.0)}
		elif lname.contains("Fireplace"):
			match time_val:
				TimeManager.TimeOfDay.DAY:
					return {"energy": base_e * 0.55, "color": base_c}
				TimeManager.TimeOfDay.AFTERNOON:
					return {"energy": base_e * 0.95, "color": base_c}
				TimeManager.TimeOfDay.NIGHT:
					return {"energy": base_e * 1.35, "color": base_c}

	if map_name.contains("Guarida"):
		return {"energy": base_e, "color": base_c}

	if lname.contains("Brazier"):
		match time_val:
			TimeManager.TimeOfDay.DAY:
				return {"energy": base_e * 0.75, "color": base_c}
			TimeManager.TimeOfDay.AFTERNOON:
				return {"energy": base_e * 1.0, "color": base_c}
			TimeManager.TimeOfDay.NIGHT:
				return {"energy": base_e * 1.35, "color": base_c}

	# Faroles exteriores y ventanas de la cabaña
	match time_val:
		TimeManager.TimeOfDay.DAY:
			return {"energy": 0.0, "color": base_c}
		TimeManager.TimeOfDay.AFTERNOON:
			return {"energy": base_e * 0.80, "color": base_c}
		TimeManager.TimeOfDay.NIGHT:
			return {"energy": base_e * 1.45, "color": base_c}

	return {"energy": base_e, "color": base_c}


func _update_time_button_visuals(time_val: TimeManager.TimeOfDay) -> void:
	if _time_button == null:
		return
	var accent := TimeManager.get_accent_color(time_val)
	_time_button.text = TimeManager.get_time_label(time_val)
	_time_button.add_theme_color_override("font_color", accent)
	_time_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

	if _time_icon_tex != null:
		var icon_idx := int(time_val)
		_time_icon_tex.region = Rect2(icon_idx * 16, 0, 16, 16)

	if _time_btn_style != null:
		_time_btn_style.border_color = accent
	if _time_btn_hover_style != null:
		_time_btn_hover_style.border_color = accent


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "StoryHUD"
	add_child(_hud_layer)

	var map_root := get_parent()
	var zone_name := "Granja de Tomás"
	if map_root != null:
		if map_root.has_meta("zone_title"):
			zone_name = str(map_root.get_meta("zone_title"))
		elif map_root.name == "GraneroInteriorMap":
			zone_name = "Cabaña de Tomás — Interior"
		elif map_root.name == "GraneroMap":
			zone_name = "La Granja y Corral de Tomás"
		elif map_root.name == "PuebloMap":
			zone_name = "El Pueblo Rural"
		elif map_root.name == "GuaridaLoboMap":
			zone_name = "Bosque Oscuro y Guarida del Lobo"

	var top_panel := PanelContainer.new()
	top_panel.position = Vector2(14, 14)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.08, 0.09, 0.12, 0.72)
	top_style.border_color = Color(0.75, 0.65, 0.42, 0.7)
	top_style.set_border_width_all(1)
	top_style.set_corner_radius_all(6)
	top_style.set_content_margin_all(8)
	top_panel.add_theme_stylebox_override("panel", top_style)
	_hud_layer.add_child(top_panel)

	var top_vbox := VBoxContainer.new()
	top_vbox.add_theme_constant_override("separation", 4)
	top_panel.add_child(top_vbox)

	# Fila superior del HUD: Título de zona + Botón compacto Día / Tarde / Noche
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)
	top_vbox.add_child(header_hbox)

	_zone_label = Label.new()
	_zone_label.text = zone_name
	_zone_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_label.add_theme_font_size_override("font_size", 15)
	_zone_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.75, 1.0))
	header_hbox.add_child(_zone_label)

	_time_icon_tex = AtlasTexture.new()
	_time_icon_tex.atlas = TIME_ICONS_TEX
	_time_icon_tex.region = Rect2(0, 0, 16, 16)

	_time_btn_style = StyleBoxFlat.new()
	_time_btn_style.bg_color = Color(0.13, 0.15, 0.20, 0.88)
	_time_btn_style.border_color = Color(0.98, 0.84, 0.36, 1.0)
	_time_btn_style.set_border_width_all(1)
	_time_btn_style.set_corner_radius_all(5)
	_time_btn_style.content_margin_left = 7
	_time_btn_style.content_margin_right = 8
	_time_btn_style.content_margin_top = 2
	_time_btn_style.content_margin_bottom = 2

	_time_btn_hover_style = _time_btn_style.duplicate() as StyleBoxFlat
	_time_btn_hover_style.bg_color = Color(0.20, 0.23, 0.30, 0.95)

	_time_button = Button.new()
	_time_button.name = "TimeCycleButton"
	_time_button.icon = _time_icon_tex
	_time_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_time_button.focus_mode = Control.FOCUS_NONE
	_time_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_time_button.tooltip_text = "Cambiar entre Día, Tarde y Noche"
	_time_button.custom_minimum_size = Vector2(74, 24)
	_time_button.add_theme_font_size_override("font_size", 13)
	_time_button.add_theme_constant_override("h_separation", 5)
	_time_button.add_theme_stylebox_override("normal", _time_btn_style)
	_time_button.add_theme_stylebox_override("hover", _time_btn_hover_style)
	_time_button.add_theme_stylebox_override("pressed", _time_btn_hover_style)
	_time_button.pressed.connect(_on_time_button_pressed)
	header_hbox.add_child(_time_button)
	_update_time_button_visuals(TimeManager.current_time)

	var hint_lbl := Label.new()
	hint_lbl.text = "WASD Mover  |  Shift Correr  |  C Sigilo  |  E Interactuar  |  F Encendedor"
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 0.9))
	top_vbox.add_child(hint_lbl)

	# Fila de estado: Encendedor + Sigilo
	var status_hbox := HBoxContainer.new()
	status_hbox.add_theme_constant_override("separation", 12)
	top_vbox.add_child(status_hbox)

	var lighter_box := HBoxContainer.new()
	lighter_box.add_theme_constant_override("separation", 4)
	status_hbox.add_child(lighter_box)

	var lighter_atlas := AtlasTexture.new()
	lighter_atlas.atlas = LIGHTER_TEX
	lighter_atlas.region = Rect2(24, 22, 14, 22)

	_lighter_icon_rect = TextureRect.new()
	_lighter_icon_rect.texture = lighter_atlas
	_lighter_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_lighter_icon_rect.custom_minimum_size = Vector2(12, 16)
	_lighter_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lighter_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lighter_box.add_child(_lighter_icon_rect)

	_lighter_status_label = Label.new()
	_lighter_status_label.add_theme_font_size_override("font_size", 11)
	lighter_box.add_child(_lighter_status_label)

	_stealth_status_label = Label.new()
	_stealth_status_label.add_theme_font_size_override("font_size", 11)
	status_hbox.add_child(_stealth_status_label)

	_refresh_status_hud()

	# Bottom dialogue / inspection panel
	_dialog_panel = PanelContainer.new()
	_dialog_panel.visible = false
	_dialog_panel.anchor_left = 0.5
	_dialog_panel.anchor_right = 0.5
	_dialog_panel.anchor_top = 1.0
	_dialog_panel.anchor_bottom = 1.0
	_dialog_panel.offset_left = -280
	_dialog_panel.offset_right = 280
	_dialog_panel.offset_top = -126
	_dialog_panel.offset_bottom = -18

	var dlg_style := StyleBoxFlat.new()
	dlg_style.bg_color = Color(0.07, 0.08, 0.11, 0.90)
	dlg_style.border_color = Color(0.86, 0.72, 0.44, 0.92)
	dlg_style.set_border_width_all(2)
	dlg_style.set_corner_radius_all(8)
	dlg_style.set_content_margin_all(12)
	_dialog_panel.add_theme_stylebox_override("panel", dlg_style)
	_hud_layer.add_child(_dialog_panel)

	var vbox := VBoxContainer.new()
	_dialog_panel.add_child(vbox)

	_dialog_title = Label.new()
	_dialog_title.add_theme_font_size_override("font_size", 15)
	_dialog_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45, 1.0))
	vbox.add_child(_dialog_title)

	_dialog_body = Label.new()
	_dialog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_body.add_theme_font_size_override("font_size", 14)
	_dialog_body.add_theme_color_override("font_color", Color(0.95, 0.95, 0.96, 1.0))
	vbox.add_child(_dialog_body)


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
