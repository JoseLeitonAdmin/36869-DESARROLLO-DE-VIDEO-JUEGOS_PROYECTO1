class_name Pastor
extends CharacterBody2D

const TIME_ICONS_TEX: Texture2D = preload("res://assets/effects/time_icons.png")

@export var walk_speed: float = 110.0
@export var sprint_speed: float = 165.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = get_node_or_null("Camera2D")
@onready var lantern: PointLight2D = get_node_or_null("LanternLight")

var _hud_layer: CanvasLayer = null
var _zone_label: Label = null
var _time_button: Button = null
var _time_icon_tex: AtlasTexture = null
var _time_btn_style: StyleBoxFlat = null
var _time_btn_hover_style: StyleBoxFlat = null
var _dialog_panel: PanelContainer = null
var _dialog_title: Label = null
var _dialog_body: Label = null
var _dialog_timer: float = 0.0
var _lantern_on: bool = false
var _time_tween: Tween = null


func _ready() -> void:
	add_to_group("player")
	_apply_transition_spawn()
	_configure_camera_limits()
	_cache_map_lights()
	_build_hud()

	if not TimeManager.time_changed.is_connected(_on_time_changed):
		TimeManager.time_changed.connect(_on_time_changed)

	_apply_time_of_day(TimeManager.current_time, true)

	if animated_sprite and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation(&"idle"):
			animated_sprite.play(&"idle")


func _exit_tree() -> void:
	if TimeManager.time_changed.is_connected(_on_time_changed):
		TimeManager.time_changed.disconnect(_on_time_changed)


func _process(delta: float) -> void:
	if _dialog_panel != null and _dialog_panel.visible and _dialog_timer > 0.0:
		_dialog_timer -= delta
		if _dialog_timer <= 0.0:
			_dialog_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			if key_ev.keycode == KEY_F:
				_toggle_lantern()
			elif _dialog_panel != null and _dialog_panel.visible and (key_ev.keycode == KEY_ESCAPE or key_ev.keycode == KEY_E or key_ev.keycode == KEY_SPACE):
				_dialog_panel.visible = false
				get_viewport().set_input_as_handled()


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


func show_story_message(title_text: String, body_text: String) -> void:
	if _dialog_panel == null:
		return
	_dialog_title.text = title_text
	_dialog_body.text = body_text
	_dialog_panel.visible = true
	_dialog_timer = 7.0


func _toggle_lantern() -> void:
	_lantern_on = not _lantern_on
	if lantern != null:
		lantern.enabled = _lantern_on


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

	# Auto-encender linterna de noche o en la guarida; apagar en exteriores de día
	if lantern != null:
		if time_val == TimeManager.TimeOfDay.NIGHT or map_name.contains("Guarida"):
			_lantern_on = true
		elif time_val == TimeManager.TimeOfDay.DAY:
			_lantern_on = false
		lantern.enabled = _lantern_on

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
	hint_lbl.text = "WASD Mover  |  Shift Correr  |  E Interactuar  |  F Linterna"
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 0.9))
	top_vbox.add_child(hint_lbl)

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
