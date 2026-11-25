class_name Pastor
extends CharacterBody2D

const LIGHTER_TEX: Texture2D = preload("res://assets/player/Lighter.png")
const SHEEP_SHEET_TEX: Texture2D = preload("res://assets/npc/sheep/Sheep-Sheet.png")

const HUD_FRAME_F_TEX: Texture2D = preload("res://assets/hud/20250420manaSoul9SlicesF-Sheet.png")
const HUD_HEADER_A_TEX: Texture2D = preload("res://assets/hud/20250420manaSoulHeaderA-Sheet.png")
const HUD_TAB_A_TEX: Texture2D = preload("res://assets/hud/20250420manaTabA-Sheet.png")
const HUD_CLOSE_BTN_TEX: Texture2D = preload("res://assets/hud/20250425closeButton-Sheet.png")
const HUD_EXIT_BTN_TEX: Texture2D = preload("res://assets/hud/20250425exitButton-Sheet.png")
const HUD_HELP_BTN_TEX: Texture2D = preload("res://assets/hud/20250425helpButton-Sheet.png")
const HUD_OPTIONS_BTN_TEX: Texture2D = preload("res://assets/hud/20250425optionsButton-Sheet.png")

const INVENTORY_SLOT_COUNT: int = 5

@export var walk_speed: float = 110.0
@export var sprint_speed: float = 165.0
@export var stealth_speed: float = 62.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var held_lantern: Sprite2D = get_node_or_null("HeldLantern")
@onready var camera: Camera2D = get_node_or_null("Camera2D")
@onready var lantern: PointLight2D = get_node_or_null("LanternLight")

var _hud_layer: CanvasLayer = null
var _sheep_count_label: Label = null
var _hud_sheep_sprite: AnimatedSprite2D = null

var _slot_bg_rects: Array[NinePatchRect] = []
var _slot_icon_rects: Array[TextureRect] = []
var _inventory_caption_label: Label = null

var _dialog_panel: Control = null
var _dialog_title: Label = null
var _dialog_body: Label = null
var _dialog_timer: float = 0.0

var _pause_menu: Control = null
var _pause_info_label: Label = null
var _pause_time_btn: Button = null
var _pause_help_box: Control = null
var _pause_feedback_label: Label = null

var _bed_menu: Control = null
var _bed_status_label: Label = null
var _bed_feedback_label: Label = null

var _game_over_menu: Control = null
var _game_over_summary_label: Label = null

var _time_tween: Tween = null
var _facing_dir: String = "down"
var _facing_left: bool = false
var _aim_angle: float = PI * 0.5
var _is_stealth: bool = false
var _base_lantern_energy: float = 1.55
var _lantern_flicker_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("player")
	_setup_directional_lantern()

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
	if not GameState.sheep_changed.is_connected(_on_sheep_changed):
		GameState.sheep_changed.connect(_on_sheep_changed)
	if not GameState.inventory_changed.is_connected(_on_inventory_changed):
		GameState.inventory_changed.connect(_on_inventory_changed)

	_apply_time_of_day(TimeManager.current_time, true)
	_sync_lantern_visual()
	_apply_stealth_visual()
	_refresh_sheep_hud()
	_refresh_inventory_hud()
	_update_animation(Vector2.ZERO, false)


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false
	if TimeManager.time_changed.is_connected(_on_time_changed):
		TimeManager.time_changed.disconnect(_on_time_changed)
	if GameState.lighter_collected.is_connected(_on_lighter_state_changed):
		GameState.lighter_collected.disconnect(_on_lighter_state_changed)
	if GameState.lighter_toggled.is_connected(_on_lighter_toggled):
		GameState.lighter_toggled.disconnect(_on_lighter_toggled)
	if GameState.sheep_changed.is_connected(_on_sheep_changed):
		GameState.sheep_changed.disconnect(_on_sheep_changed)
	if GameState.inventory_changed.is_connected(_on_inventory_changed):
		GameState.inventory_changed.disconnect(_on_inventory_changed)


func _setup_directional_lantern() -> void:
	if lantern == null:
		return
	_base_lantern_energy = 1.55
	lantern.energy = _base_lantern_energy
	lantern.texture = _create_directional_cone_texture()
	lantern.texture_scale = 2.35
	lantern.rotation = _aim_angle


func _create_directional_cone_texture() -> ImageTexture:
	# Genera una textura direccional centrada en la lámpara:
	# Hacia adelante (+X) proyecta un haz largo y cálido; hacia atrás (-X) solo un halo tenue y corto.
	const SIZE: int = 96
	const HALF: float = 48.0
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	for y in range(SIZE):
		var dy := (float(y) - HALF) / HALF
		for x in range(SIZE):
			var dx := (float(x) - HALF) / HALF
			var dist := sqrt(dx * dx + dy * dy)
			if dist >= 1.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
				continue

			var forward_dot := dx / maxf(dist, 0.0001)

			# Halo trasero/cercano muy suave y corto (solo ~22% del radio y baja intensidad)
			var rear_t := clampf(1.0 - (dist / 0.22), 0.0, 1.0)
			var rear_glow := rear_t * rear_t * 0.28

			# Haz frontal principal hacia donde mira el pastor
			var cone_t := clampf((forward_dot - 0.02) / 0.98, 0.0, 1.0)
			var cone_angle := pow(cone_t, 1.35)
			var forward_dist_t := clampf(1.0 - (dist / 0.98), 0.0, 1.0)
			var forward_beam := cone_angle * pow(forward_dist_t, 1.2)

			var alpha := clampf(maxf(forward_beam, rear_glow), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if _dialog_panel != null and _dialog_panel.visible and _dialog_timer > 0.0 and not is_menu_open():
		_dialog_timer -= delta
		if _dialog_timer <= 0.0:
			_dialog_panel.visible = false

	if lantern != null and lantern.enabled:
		_lantern_flicker_time += delta
		lantern.energy = _base_lantern_energy + sin(_lantern_flicker_time * 9.0) * 0.06 + sin(_lantern_flicker_time * 17.3) * 0.03
		lantern.rotation = lerp_angle(lantern.rotation, _aim_angle, clampf(delta * 16.0, 0.0, 1.0))
		_update_held_lantern_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			if is_dialog_active():
				if key_ev.keycode == KEY_E:
					var dialogic_node := get_node_or_null("/root/Dialogic")
					if dialogic_node != null and int(dialogic_node.get("current_state")) != 2:
						var inputs_sub: Node = dialogic_node.get("Inputs") as Node
						if inputs_sub != null and inputs_sub.has_method("handle_input"):
							inputs_sub.call("handle_input")
							get_viewport().set_input_as_handled()
				return

			if key_ev.keycode == KEY_ESCAPE:
				if _game_over_menu != null and _game_over_menu.visible:
					get_viewport().set_input_as_handled()
					return
				if _bed_menu != null and _bed_menu.visible:
					close_bed_save_menu()
				elif _dialog_panel != null and _dialog_panel.visible:
					_dialog_panel.visible = false
				else:
					toggle_pause_menu()
				get_viewport().set_input_as_handled()
				return

			if is_menu_open():
				return

			if key_ev.keycode == KEY_F:
				_toggle_lantern()
			elif key_ev.keycode == KEY_C:
				_toggle_stealth()
			elif _dialog_panel != null and _dialog_panel.visible and (key_ev.keycode == KEY_E or key_ev.keycode == KEY_SPACE):
				_dialog_panel.visible = false
				get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if get_tree().paused or is_menu_open() or is_dialog_active():
		velocity = Vector2.ZERO
		_update_animation(Vector2.ZERO, false)
		return

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

	match _facing_dir:
		"down":
			_aim_angle = PI * 0.5
		"up":
			_aim_angle = -PI * 0.5
		"side":
			_aim_angle = PI if _facing_left else 0.0

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
		if not is_inside_tree():
			lantern.rotation = _aim_angle


func is_stealth_active() -> bool:
	return _is_stealth


func get_stealth_detection_multiplier() -> float:
	return 0.45 if _is_stealth else 1.0


func get_lantern_aim_angle() -> float:
	return _aim_angle


func is_menu_open() -> bool:
	var pause_open := _pause_menu != null and _pause_menu.visible
	var bed_open := _bed_menu != null and _bed_menu.visible
	var game_over_open := _game_over_menu != null and _game_over_menu.visible
	return pause_open or bed_open or game_over_open


func is_game_over_open() -> bool:
	return _game_over_menu != null and _game_over_menu.visible


func open_game_over_menu() -> void:
	if _game_over_menu == null:
		return
	if _pause_menu != null:
		_pause_menu.visible = false
	if _bed_menu != null:
		_bed_menu.visible = false
	if _dialog_panel != null:
		_dialog_panel.visible = false
	var dialogic_node := get_node_or_null("/root/Dialogic")
	if dialogic_node != null and dialogic_node.get("current_timeline") != null:
		dialogic_node.call("end_timeline", true)
	if _game_over_summary_label != null:
		_game_over_summary_label.text = (
			"Te has quedado sin ovejas en la Noche " + str(GameState.current_night) + ".\n"
			+ "El Lobo sobrenatural ha devorado tu último vínculo con el pueblo."
		)
	_game_over_menu.visible = true
	_sync_tree_pause()


func close_game_over_menu() -> void:
	if _game_over_menu == null:
		return
	_game_over_menu.visible = false
	_sync_tree_pause()


func is_dialog_active() -> bool:
	var dialogic_node := get_node_or_null("/root/Dialogic")
	return dialogic_node != null and dialogic_node.get("current_timeline") != null


func hide_story_message() -> void:
	if _dialog_panel != null:
		_dialog_panel.visible = false
	_dialog_timer = 0.0


func show_story_message(title_text: String, body_text: String) -> void:
	if _dialog_panel == null:
		return
	_dialog_title.text = title_text
	_dialog_body.text = body_text
	_dialog_panel.visible = true
	_dialog_timer = 6.5


func toggle_pause_menu() -> void:
	if _pause_menu == null:
		return
	if _bed_menu != null and _bed_menu.visible:
		_bed_menu.visible = false
	var next_vis := not _pause_menu.visible
	_pause_menu.visible = next_vis
	if next_vis:
		if _pause_feedback_label != null:
			_pause_feedback_label.text = ""
		_refresh_pause_menu_labels()
	_sync_tree_pause()


func open_bed_save_menu() -> void:
	if _bed_menu == null:
		return
	if _pause_menu != null:
		_pause_menu.visible = false
	if _dialog_panel != null:
		_dialog_panel.visible = false
	_bed_menu.visible = true
	if _bed_feedback_label != null:
		_bed_feedback_label.text = "Elige una opción para descansar o guardar tu progreso."
	_refresh_bed_menu_labels()
	_sync_tree_pause()


func close_bed_save_menu() -> void:
	if _bed_menu == null:
		return
	_bed_menu.visible = false
	_sync_tree_pause()


func _sync_tree_pause() -> void:
	if get_tree() != null:
		get_tree().paused = is_menu_open()


func _toggle_stealth() -> void:
	_is_stealth = not _is_stealth
	_apply_stealth_visual()
	_update_animation(_get_movement_input(), false)


func _apply_stealth_visual() -> void:
	if animated_sprite != null:
		animated_sprite.modulate = Color(0.84, 0.88, 0.98, 0.90) if _is_stealth else Color(1.0, 1.0, 1.0, 1.0)
	_refresh_inventory_hud()


func _toggle_lantern() -> void:
	if not GameState.has_lighter:
		show_story_message("Sin lámpara", "Aún no tienes la lámpara. Búscala sobre la mesa dentro de tu cabaña.")
		return
	GameState.toggle_lighter()


func _on_lighter_state_changed() -> void:
	_sync_lantern_visual()
	_refresh_inventory_hud()


func _on_lighter_toggled(_is_on: bool) -> void:
	_sync_lantern_visual()
	_refresh_inventory_hud()


func _on_sheep_changed(new_count: int) -> void:
	_refresh_sheep_hud()
	_refresh_pause_menu_labels()
	_refresh_bed_menu_labels()
	if new_count <= 0:
		open_game_over_menu()


func _on_inventory_changed() -> void:
	_refresh_inventory_hud()
	_refresh_bed_menu_labels()


func _sync_lantern_visual() -> void:
	var active := GameState.has_lighter and GameState.lighter_on
	if held_lantern != null:
		held_lantern.visible = active
	if lantern != null:
		lantern.enabled = active
		if active:
			lantern.energy = _base_lantern_energy
			lantern.rotation = _aim_angle
	_update_held_lantern_transform()


func _refresh_sheep_hud() -> void:
	if _sheep_count_label != null:
		_sheep_count_label.text = str(GameState.sheep_count)


func _refresh_inventory_hud() -> void:
	if _slot_bg_rects.is_empty():
		return

	var items := GameState.inventory
	var active_captions: PackedStringArray = PackedStringArray()

	for i in range(INVENTORY_SLOT_COUNT):
		var bg_rect := _slot_bg_rects[i]
		var icon_rect := _slot_icon_rects[i]

		if i < items.size():
			var item: Dictionary = items[i]
			var item_id: String = str(item.get("id", ""))
			var item_name: String = str(item.get("name", "Objeto"))
			var icon_path: String = str(item.get("icon", ""))

			var is_active := (item_id == "lighter" and GameState.lighter_on)
			bg_rect.texture = HUD_HEADER_A_TEX
			if is_active:
				bg_rect.self_modulate = Color(1.0, 0.94, 0.74, 0.90)
			else:
				bg_rect.self_modulate = Color(0.94, 0.86, 0.70, 0.78)

			if item_id == "lighter":
				var lighter_atlas := AtlasTexture.new()
				lighter_atlas.atlas = LIGHTER_TEX
				lighter_atlas.region = Rect2(24, 22, 14, 22)
				icon_rect.texture = lighter_atlas
				active_captions.append("Lámpara [F]: " + ("Encendida" if GameState.lighter_on else "Apagada"))
			elif not icon_path.is_empty() and ResourceLoader.exists(icon_path):
				icon_rect.texture = load(icon_path) as Texture2D
				active_captions.append(item_name)
			else:
				icon_rect.texture = null
				active_captions.append(item_name)

			icon_rect.visible = true
			icon_rect.modulate = Color(1.0, 0.97, 0.90, 0.95)
			bg_rect.tooltip_text = item_name
		else:
			bg_rect.texture = HUD_FRAME_F_TEX
			bg_rect.self_modulate = Color(0.76, 0.65, 0.50, 0.55)
			bg_rect.tooltip_text = "Ranura vacía"
			icon_rect.texture = null
			icon_rect.visible = false

	if _inventory_caption_label != null:
		if active_captions.is_empty():
			_inventory_caption_label.text = "Inventario"
		else:
			_inventory_caption_label.text = "  •  ".join(active_captions)


func _refresh_pause_menu_labels() -> void:
	if _pause_info_label != null:
		_pause_info_label.text = (
			_get_current_zone_name()
			+ "\nNoche " + str(GameState.current_night)
			+ "  •  Hora: " + TimeManager.get_time_label()
			+ "  •  Ovejas (Vida): " + str(GameState.sheep_count)
		)
	if _pause_time_btn != null:
		_pause_time_btn.text = "Cambiar Hora (" + TimeManager.get_time_label() + ")"


func _refresh_bed_menu_labels() -> void:
	if _bed_status_label != null:
		_bed_status_label.text = (
			"Noche " + str(GameState.current_night)
			+ " (" + TimeManager.get_time_label() + ")\n"
			+ "Ovejas en el rebaño (Vida): " + str(GameState.sheep_count) + " / " + str(GameState.max_sheep)
			+ "\nObjetos obtenidos: " + str(GameState.inventory.size())
		)


func _get_current_zone_name() -> String:
	var map_root := get_parent()
	if map_root != null:
		if map_root.has_meta("zone_title"):
			return str(map_root.get_meta("zone_title"))
		elif map_root.name == "GraneroInteriorMap":
			return "Cabaña de Tomás — Interior"
		elif map_root.name == "GraneroMap":
			return "La Granja y Corral de Tomás"
		elif map_root.name == "PuebloMap":
			return "El Pueblo Rural"
		elif map_root.name == "GuaridaLoboMap":
			return "Bosque Oscuro y Guarida del Lobo"
	return "Granja de Tomás"


func _get_current_map_path() -> String:
	var map_root := get_parent()
	if map_root != null and not map_root.scene_file_path.is_empty():
		return map_root.scene_file_path
	return "res://scenes/maps/granero_interior.tscn"


func _on_bed_save_pressed() -> void:
	var ok := GameState.save_game(_get_current_map_path(), global_position)
	_refresh_bed_menu_labels()
	if _bed_feedback_label != null:
		_bed_feedback_label.text = "✓ ¡Partida guardada en el diario!" if ok else "Error al guardar la partida."


func _on_bed_sleep_and_save_pressed() -> void:
	var prev_time := TimeManager.current_time
	TimeManager.cycle_time()
	if prev_time == TimeManager.TimeOfDay.NIGHT:
		GameState.current_night += 1
	var ok := GameState.save_game(_get_current_map_path(), global_position)
	_refresh_bed_menu_labels()
	_refresh_pause_menu_labels()
	if _bed_feedback_label != null:
		if ok:
			_bed_feedback_label.text = "✓ Descansaste y guardaste (Noche " + str(GameState.current_night) + " — " + TimeManager.get_time_label() + ")."
		else:
			_bed_feedback_label.text = "Error al guardar la partida."


func _on_pause_cycle_time_pressed() -> void:
	TimeManager.cycle_time()
	_refresh_pause_menu_labels()
	_refresh_bed_menu_labels()


func _on_pause_load_pressed() -> void:
	if not GameState.has_save_game():
		if _pause_feedback_label != null:
			_pause_feedback_label.text = "Aún no hay una partida guardada en la cama."
		return
	var ok := GameState.load_game()
	if ok:
		_refresh_sheep_hud()
		_refresh_inventory_hud()
		_refresh_pause_menu_labels()
		if _pause_feedback_label != null:
			_pause_feedback_label.text = "✓ Partida cargada (Noche " + str(GameState.current_night) + ", Ovejas: " + str(GameState.sheep_count) + ")."


func _on_pause_help_pressed() -> void:
	if _pause_help_box != null:
		_pause_help_box.visible = not _pause_help_box.visible


func _on_pause_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


func _on_game_over_restart_pressed() -> void:
	close_game_over_menu()
	get_tree().paused = false
	GameState.reset_state()
	TimeManager.set_time(TimeManager.TimeOfDay.DAY)
	MapTransition.next_spawn_point = "Default"
	_refresh_sheep_hud()
	_refresh_inventory_hud()
	if get_tree() != null and get_tree().current_scene != null:
		get_tree().change_scene_to_file("res://scenes/maps/granero.tscn")
	else:
		_apply_transition_spawn()


func _on_game_over_load_save_pressed() -> void:
	if not GameState.has_save_game():
		_on_game_over_restart_pressed()
		return
	close_game_over_menu()
	get_tree().paused = false
	var ok := GameState.load_game()
	if not ok:
		_on_game_over_restart_pressed()
		return
	if GameState.sheep_count <= 0:
		GameState.set_sheep_count(GameState.max_sheep)
	_refresh_sheep_hud()
	_refresh_inventory_hud()
	var target_map := GameState.last_saved_map if not GameState.last_saved_map.is_empty() else "res://scenes/maps/granero.tscn"
	if get_tree() != null and get_tree().current_scene != null and ResourceLoader.exists(target_map):
		MapTransition.next_spawn_point = ""
		get_tree().change_scene_to_file(target_map)
	elif GameState.last_saved_pos != Vector2.ZERO:
		global_position = GameState.last_saved_pos


func _on_time_changed(new_time: TimeManager.TimeOfDay) -> void:
	if not is_inside_tree():
		return
	_apply_time_of_day(new_time, false)
	_refresh_pause_menu_labels()
	_refresh_bed_menu_labels()


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

	match time_val:
		TimeManager.TimeOfDay.DAY:
			return {"energy": 0.0, "color": base_c}
		TimeManager.TimeOfDay.AFTERNOON:
			return {"energy": base_e * 0.80, "color": base_c}
		TimeManager.TimeOfDay.NIGHT:
			return {"energy": base_e * 1.45, "color": base_c}

	return {"energy": base_e, "color": base_c}


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "StoryHUD"
	_hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hud_layer)

	_build_top_left_sheep_hud()
	_build_bottom_inventory_hud()
	_build_story_dialog_hud()
	_build_pause_menu_hud()
	_build_bed_save_menu_hud()
	_build_game_over_menu_hud()


func _build_top_left_sheep_hud() -> void:
	var life_box := NinePatchRect.new()
	life_box.name = "SheepLifeHUD"
	life_box.texture = HUD_HEADER_A_TEX
	life_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	life_box.self_modulate = Color(0.96, 0.90, 0.76, 0.76)
	life_box.patch_margin_left = 20
	life_box.patch_margin_top = 8
	life_box.patch_margin_right = 20
	life_box.patch_margin_bottom = 8
	life_box.position = Vector2(14, 14)
	life_box.size = Vector2(106, 46)
	_hud_layer.add_child(life_box)

	var sf := SpriteFrames.new()
	sf.add_animation(&"idle")
	sf.set_animation_loop(&"idle", true)
	sf.set_animation_speed(&"idle", 3.5)
	for i in range(4):
		var at := AtlasTexture.new()
		at.atlas = SHEEP_SHEET_TEX
		at.region = Rect2(i * 32, 0, 32, 32)
		sf.add_frame(&"idle", at)

	_hud_sheep_sprite = AnimatedSprite2D.new()
	_hud_sheep_sprite.name = "AnimatedSheepIcon"
	_hud_sheep_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hud_sheep_sprite.sprite_frames = sf
	_hud_sheep_sprite.animation = &"idle"
	_hud_sheep_sprite.autoplay = "idle"
	_hud_sheep_sprite.position = Vector2(32, 35)
	_hud_sheep_sprite.scale = Vector2(1.25, 1.25)
	_hud_sheep_sprite.offset = Vector2(0, -10)
	_hud_sheep_sprite.modulate = Color(1.0, 0.97, 0.90, 0.92)
	life_box.add_child(_hud_sheep_sprite)
	_hud_sheep_sprite.play(&"idle")

	_sheep_count_label = Label.new()
	_sheep_count_label.name = "SheepCountLabel"
	_sheep_count_label.position = Vector2(50, 7)
	_sheep_count_label.size = Vector2(42, 32)
	_sheep_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sheep_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sheep_count_label.text = str(GameState.sheep_count)

	var ls := LabelSettings.new()
	ls.font_size = 19
	ls.font_color = Color(0.26, 0.14, 0.06, 0.95)
	ls.outline_size = 3
	ls.outline_color = Color(0.98, 0.92, 0.76, 0.85)
	_sheep_count_label.label_settings = ls
	life_box.add_child(_sheep_count_label)


func _build_bottom_inventory_hud() -> void:
	var inv_root := Control.new()
	inv_root.name = "InventoryBarHUD"
	inv_root.anchor_left = 0.5
	inv_root.anchor_right = 0.5
	inv_root.anchor_top = 1.0
	inv_root.anchor_bottom = 1.0
	inv_root.offset_left = -135
	inv_root.offset_right = 135
	inv_root.offset_top = -72
	inv_root.offset_bottom = -10
	_hud_layer.add_child(inv_root)

	_inventory_caption_label = Label.new()
	_inventory_caption_label.position = Vector2(0, 0)
	_inventory_caption_label.size = Vector2(270, 18)
	_inventory_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cap_ls := LabelSettings.new()
	cap_ls.font_size = 11
	cap_ls.font_color = Color(0.95, 0.87, 0.68, 0.82)
	cap_ls.outline_size = 3
	cap_ls.outline_color = Color(0.14, 0.09, 0.05, 0.85)
	_inventory_caption_label.label_settings = cap_ls
	inv_root.add_child(_inventory_caption_label)

	var slots_hbox := HBoxContainer.new()
	slots_hbox.position = Vector2(15, 18)
	slots_hbox.size = Vector2(240, 42)
	slots_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_hbox.add_theme_constant_override("separation", 6)
	inv_root.add_child(slots_hbox)

	_slot_bg_rects.clear()
	_slot_icon_rects.clear()

	for i in range(INVENTORY_SLOT_COUNT):
		var slot_frame := NinePatchRect.new()
		slot_frame.name = "Slot_" + str(i)
		slot_frame.texture = HUD_FRAME_F_TEX
		slot_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slot_frame.self_modulate = Color(0.76, 0.65, 0.50, 0.55)
		slot_frame.patch_margin_left = 10
		slot_frame.patch_margin_top = 10
		slot_frame.patch_margin_right = 10
		slot_frame.patch_margin_bottom = 10
		slot_frame.custom_minimum_size = Vector2(42, 42)
		slots_hbox.add_child(slot_frame)
		_slot_bg_rects.append(slot_frame)

		var icon_rect := TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.position = Vector2(10, 10)
		icon_rect.size = Vector2(22, 22)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_frame.add_child(icon_rect)
		_slot_icon_rects.append(icon_rect)


func _build_story_dialog_hud() -> void:
	_dialog_panel = NinePatchRect.new()
	_dialog_panel.name = "DialogToast"
	var np := _dialog_panel as NinePatchRect
	np.texture = HUD_HEADER_A_TEX
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.self_modulate = Color(0.95, 0.88, 0.74, 0.86)
	np.patch_margin_left = 24
	np.patch_margin_top = 10
	np.patch_margin_right = 24
	np.patch_margin_bottom = 10
	_dialog_panel.visible = false
	_dialog_panel.anchor_left = 0.5
	_dialog_panel.anchor_right = 0.5
	_dialog_panel.anchor_top = 1.0
	_dialog_panel.anchor_bottom = 1.0
	_dialog_panel.offset_left = -260
	_dialog_panel.offset_right = 260
	_dialog_panel.offset_top = -176
	_dialog_panel.offset_bottom = -82
	_hud_layer.add_child(_dialog_panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(28, 12)
	vbox.size = Vector2(464, 68)
	vbox.add_theme_constant_override("separation", 3)
	_dialog_panel.add_child(vbox)

	_dialog_title = Label.new()
	var title_ls := LabelSettings.new()
	title_ls.font_size = 14
	title_ls.font_color = Color(0.38, 0.18, 0.06, 1.0)
	title_ls.outline_size = 2
	title_ls.outline_color = Color(0.98, 0.92, 0.78, 0.85)
	_dialog_title.label_settings = title_ls
	vbox.add_child(_dialog_title)

	_dialog_body = Label.new()
	_dialog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var body_ls := LabelSettings.new()
	body_ls.font_size = 13
	body_ls.font_color = Color(0.22, 0.13, 0.06, 0.98)
	body_ls.outline_size = 1
	body_ls.outline_color = Color(0.98, 0.92, 0.78, 0.65)
	_dialog_body.label_settings = body_ls
	vbox.add_child(_dialog_body)


func _build_pause_menu_hud() -> void:
	_pause_menu = Control.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.visible = false
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer.add_child(_pause_menu)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.08, 0.05, 0.03, 0.56)
	_pause_menu.add_child(dimmer)

	var frame := NinePatchRect.new()
	frame.texture = HUD_FRAME_F_TEX
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.self_modulate = Color(0.90, 0.78, 0.60, 0.88)
	frame.patch_margin_left = 20
	frame.patch_margin_top = 20
	frame.patch_margin_right = 20
	frame.patch_margin_bottom = 20
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -190
	frame.offset_right = 190
	frame.offset_top = -175
	frame.offset_bottom = 175
	_pause_menu.add_child(frame)

	var parchment_inner := NinePatchRect.new()
	parchment_inner.texture = HUD_HEADER_A_TEX
	parchment_inner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parchment_inner.self_modulate = Color(0.96, 0.90, 0.78, 0.86)
	parchment_inner.patch_margin_left = 20
	parchment_inner.patch_margin_top = 10
	parchment_inner.patch_margin_right = 20
	parchment_inner.patch_margin_bottom = 10
	parchment_inner.position = Vector2(14, 16)
	parchment_inner.size = Vector2(352, 320)
	frame.add_child(parchment_inner)

	var header := NinePatchRect.new()
	header.texture = HUD_HEADER_A_TEX
	header.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header.self_modulate = Color(1.0, 0.94, 0.80, 0.94)
	header.patch_margin_left = 24
	header.patch_margin_top = 8
	header.patch_margin_right = 24
	header.patch_margin_bottom = 8
	header.position = Vector2(70, -14)
	header.size = Vector2(240, 42)
	frame.add_child(header)

	var header_lbl := Label.new()
	header_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_lbl.text = "MENÚ DE PAUSA"
	var h_ls := LabelSettings.new()
	h_ls.font_size = 15
	h_ls.font_color = Color(0.28, 0.15, 0.07, 1.0)
	h_ls.outline_size = 2
	h_ls.outline_color = Color(1.0, 0.94, 0.78, 0.9)
	header_lbl.label_settings = h_ls
	header.add_child(header_lbl)

	var close_btn := _create_diamond_icon_button(HUD_CLOSE_BTN_TEX, "Cerrar menú [ESC]")
	close_btn.position = Vector2(334, 14)
	close_btn.pressed.connect(toggle_pause_menu)
	frame.add_child(close_btn)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(32, 36)
	vbox.size = Vector2(316, 294)
	vbox.add_theme_constant_override("separation", 8)
	frame.add_child(vbox)

	_pause_info_label = Label.new()
	_pause_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var info_ls := LabelSettings.new()
	info_ls.font_size = 12
	info_ls.font_color = Color(0.28, 0.16, 0.08, 0.96)
	info_ls.outline_size = 2
	info_ls.outline_color = Color(0.98, 0.92, 0.78, 0.8)
	_pause_info_label.label_settings = info_ls
	vbox.add_child(_pause_info_label)

	var resume_btn := _create_hud_menu_button("Reanudar Partida [ESC]", HUD_CLOSE_BTN_TEX)
	resume_btn.pressed.connect(toggle_pause_menu)
	vbox.add_child(resume_btn)

	_pause_time_btn = _create_hud_menu_button("Cambiar Hora", HUD_OPTIONS_BTN_TEX)
	_pause_time_btn.pressed.connect(_on_pause_cycle_time_pressed)
	vbox.add_child(_pause_time_btn)

	var load_btn := _create_hud_menu_button("Cargar Último Guardado", HUD_OPTIONS_BTN_TEX)
	load_btn.pressed.connect(_on_pause_load_pressed)
	vbox.add_child(load_btn)

	var help_btn := _create_hud_menu_button("Controles y Ayuda", HUD_HELP_BTN_TEX)
	help_btn.pressed.connect(_on_pause_help_pressed)
	vbox.add_child(help_btn)

	_pause_help_box = NinePatchRect.new()
	var hb := _pause_help_box as NinePatchRect
	hb.texture = HUD_HEADER_A_TEX
	hb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hb.self_modulate = Color(0.94, 0.86, 0.70, 0.88)
	hb.patch_margin_left = 16
	hb.patch_margin_top = 8
	hb.patch_margin_right = 16
	hb.patch_margin_bottom = 8
	hb.custom_minimum_size = Vector2(300, 54)
	hb.visible = false
	vbox.add_child(_pause_help_box)

	var help_lbl := Label.new()
	help_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_lbl.text = "WASD: Mover  |  Shift: Correr  |  C: Sigilo\nE: Interactuar / Cama  |  F: Lámpara  |  ESC: Pausa"
	var hlp_ls := LabelSettings.new()
	hlp_ls.font_size = 11
	hlp_ls.font_color = Color(0.24, 0.13, 0.06, 0.98)
	help_lbl.label_settings = hlp_ls
	_pause_help_box.add_child(help_lbl)

	var quit_btn := _create_hud_menu_button("Salir del Juego", HUD_EXIT_BTN_TEX)
	quit_btn.pressed.connect(_on_pause_quit_pressed)
	vbox.add_child(quit_btn)

	_pause_feedback_label = Label.new()
	_pause_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fb_ls := LabelSettings.new()
	fb_ls.font_size = 11
	fb_ls.font_color = Color(0.24, 0.42, 0.14, 1.0)
	fb_ls.outline_size = 2
	fb_ls.outline_color = Color(0.98, 0.93, 0.80, 0.85)
	_pause_feedback_label.label_settings = fb_ls
	vbox.add_child(_pause_feedback_label)


func _build_bed_save_menu_hud() -> void:
	_bed_menu = Control.new()
	_bed_menu.name = "BedSaveMenu"
	_bed_menu.visible = false
	_bed_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer.add_child(_bed_menu)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.08, 0.05, 0.03, 0.56)
	_bed_menu.add_child(dimmer)

	var frame := NinePatchRect.new()
	frame.texture = HUD_FRAME_F_TEX
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.self_modulate = Color(0.90, 0.78, 0.60, 0.88)
	frame.patch_margin_left = 20
	frame.patch_margin_top = 20
	frame.patch_margin_right = 20
	frame.patch_margin_bottom = 20
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -185
	frame.offset_right = 185
	frame.offset_top = -145
	frame.offset_bottom = 145
	_bed_menu.add_child(frame)

	var parchment_inner := NinePatchRect.new()
	parchment_inner.texture = HUD_HEADER_A_TEX
	parchment_inner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parchment_inner.self_modulate = Color(0.96, 0.90, 0.78, 0.86)
	parchment_inner.patch_margin_left = 20
	parchment_inner.patch_margin_top = 10
	parchment_inner.patch_margin_right = 20
	parchment_inner.patch_margin_bottom = 10
	parchment_inner.position = Vector2(14, 16)
	parchment_inner.size = Vector2(342, 260)
	frame.add_child(parchment_inner)

	var header := NinePatchRect.new()
	header.texture = HUD_HEADER_A_TEX
	header.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header.self_modulate = Color(1.0, 0.94, 0.80, 0.94)
	header.patch_margin_left = 24
	header.patch_margin_top = 8
	header.patch_margin_right = 24
	header.patch_margin_bottom = 8
	header.position = Vector2(65, -14)
	header.size = Vector2(240, 42)
	frame.add_child(header)

	var header_lbl := Label.new()
	header_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_lbl.text = "CAMA — GUARDAR"
	var h_ls := LabelSettings.new()
	h_ls.font_size = 15
	h_ls.font_color = Color(0.28, 0.15, 0.07, 1.0)
	h_ls.outline_size = 2
	h_ls.outline_color = Color(1.0, 0.94, 0.78, 0.9)
	header_lbl.label_settings = h_ls
	header.add_child(header_lbl)

	var close_btn := _create_diamond_icon_button(HUD_CLOSE_BTN_TEX, "Cerrar [ESC]")
	close_btn.position = Vector2(324, 14)
	close_btn.pressed.connect(close_bed_save_menu)
	frame.add_child(close_btn)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(32, 38)
	vbox.size = Vector2(306, 232)
	vbox.add_theme_constant_override("separation", 10)
	frame.add_child(vbox)

	_bed_status_label = Label.new()
	_bed_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var st_ls := LabelSettings.new()
	st_ls.font_size = 12
	st_ls.font_color = Color(0.28, 0.16, 0.08, 0.96)
	st_ls.outline_size = 2
	st_ls.outline_color = Color(0.98, 0.92, 0.78, 0.8)
	_bed_status_label.label_settings = st_ls
	vbox.add_child(_bed_status_label)

	var save_btn := _create_hud_menu_button("Guardar Partida", HUD_OPTIONS_BTN_TEX)
	save_btn.name = "SaveButton"
	save_btn.pressed.connect(_on_bed_save_pressed)
	vbox.add_child(save_btn)

	var sleep_btn := _create_hud_menu_button("Dormir y Guardar (Avanzar Ciclo)", HUD_HELP_BTN_TEX)
	sleep_btn.name = "SleepSaveButton"
	sleep_btn.pressed.connect(_on_bed_sleep_and_save_pressed)
	vbox.add_child(sleep_btn)

	var back_btn := _create_hud_menu_button("Seguir Explorando", HUD_CLOSE_BTN_TEX)
	back_btn.pressed.connect(close_bed_save_menu)
	vbox.add_child(back_btn)

	_bed_feedback_label = Label.new()
	_bed_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bed_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bfb_ls := LabelSettings.new()
	bfb_ls.font_size = 11
	bfb_ls.font_color = Color(0.24, 0.42, 0.14, 1.0)
	bfb_ls.outline_size = 2
	bfb_ls.outline_color = Color(0.98, 0.93, 0.80, 0.85)
	_bed_feedback_label.label_settings = bfb_ls
	vbox.add_child(_bed_feedback_label)


func _build_game_over_menu_hud() -> void:
	_game_over_menu = Control.new()
	_game_over_menu.name = "GameOverMenu"
	_game_over_menu.visible = false
	_game_over_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer.add_child(_game_over_menu)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.06, 0.02, 0.02, 0.78)
	_game_over_menu.add_child(dimmer)

	var frame := NinePatchRect.new()
	frame.texture = HUD_FRAME_F_TEX
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.self_modulate = Color(0.88, 0.72, 0.56, 0.92)
	frame.patch_margin_left = 20
	frame.patch_margin_top = 20
	frame.patch_margin_right = 20
	frame.patch_margin_bottom = 20
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -195
	frame.offset_right = 195
	frame.offset_top = -150
	frame.offset_bottom = 150
	_game_over_menu.add_child(frame)

	var parchment_inner := NinePatchRect.new()
	parchment_inner.texture = HUD_HEADER_A_TEX
	parchment_inner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parchment_inner.self_modulate = Color(0.95, 0.87, 0.74, 0.90)
	parchment_inner.patch_margin_left = 20
	parchment_inner.patch_margin_top = 10
	parchment_inner.patch_margin_right = 20
	parchment_inner.patch_margin_bottom = 10
	parchment_inner.position = Vector2(14, 16)
	parchment_inner.size = Vector2(362, 268)
	frame.add_child(parchment_inner)

	var header := NinePatchRect.new()
	header.texture = HUD_HEADER_A_TEX
	header.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header.self_modulate = Color(0.98, 0.88, 0.72, 0.96)
	header.patch_margin_left = 24
	header.patch_margin_top = 8
	header.patch_margin_right = 24
	header.patch_margin_bottom = 8
	header.position = Vector2(75, -16)
	header.size = Vector2(240, 44)
	frame.add_child(header)

	var header_lbl := Label.new()
	header_lbl.name = "GameOverTitleLabel"
	header_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_lbl.text = "GAME OVER"
	var h_ls := LabelSettings.new()
	h_ls.font_size = 18
	h_ls.font_color = Color(0.52, 0.08, 0.06, 1.0)
	h_ls.outline_size = 3
	h_ls.outline_color = Color(1.0, 0.93, 0.78, 0.95)
	header_lbl.label_settings = h_ls
	header.add_child(header_lbl)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(36, 40)
	vbox.size = Vector2(318, 232)
	vbox.add_theme_constant_override("separation", 10)
	frame.add_child(vbox)

	_game_over_summary_label = Label.new()
	_game_over_summary_label.name = "GameOverMessageLabel"
	_game_over_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_game_over_summary_label.text = "Te has quedado sin ovejas.\nEl Lobo sobrenatural ha devorado tu último vínculo con el pueblo."
	var sum_ls := LabelSettings.new()
	sum_ls.font_size = 12
	sum_ls.font_color = Color(0.28, 0.14, 0.07, 0.98)
	sum_ls.outline_size = 2
	sum_ls.outline_color = Color(0.98, 0.92, 0.78, 0.85)
	_game_over_summary_label.label_settings = sum_ls
	vbox.add_child(_game_over_summary_label)

	var restart_btn := _create_hud_menu_button("Reiniciar Juego (Nueva Partida)", HUD_OPTIONS_BTN_TEX)
	restart_btn.name = "RestartGameButton"
	restart_btn.pressed.connect(_on_game_over_restart_pressed)
	vbox.add_child(restart_btn)

	var load_save_btn := _create_hud_menu_button("Reiniciar desde Último Guardado", HUD_HELP_BTN_TEX)
	load_save_btn.name = "RetrySaveButton"
	load_save_btn.pressed.connect(_on_game_over_load_save_pressed)
	vbox.add_child(load_save_btn)

	var quit_btn := _create_hud_menu_button("Salir del Juego", HUD_EXIT_BTN_TEX)
	quit_btn.name = "QuitGameButton"
	quit_btn.pressed.connect(_on_pause_quit_pressed)
	vbox.add_child(quit_btn)


func _create_hud_menu_button(label_text: String, icon_sheet: Texture2D = null) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.custom_minimum_size = Vector2(280, 34)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.26, 0.14, 0.06, 0.98))
	btn.add_theme_color_override("font_hover_color", Color(0.16, 0.08, 0.03, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.38, 0.20, 0.08, 1.0))

	if icon_sheet != null:
		var icon_at := AtlasTexture.new()
		icon_at.atlas = icon_sheet
		# Usamos el fotograma 2 (x=64..96), que tiene tonos cálidos ámbar/bronce
		icon_at.region = Rect2(64, 0, 32, 32)
		btn.icon = icon_at
		btn.add_theme_constant_override("h_separation", 8)

	btn.add_theme_stylebox_override("normal", _make_parchment_button_stylebox(2, Color(0.96, 0.89, 0.74, 0.88)))
	btn.add_theme_stylebox_override("hover", _make_parchment_button_stylebox(1, Color(1.0, 0.96, 0.84, 0.95)))
	btn.add_theme_stylebox_override("pressed", _make_parchment_button_stylebox(0, Color(0.88, 0.78, 0.62, 0.92)))
	btn.add_theme_stylebox_override("disabled", _make_parchment_button_stylebox(0, Color(0.72, 0.65, 0.54, 0.60)))
	return btn


func _make_parchment_button_stylebox(tab_idx: int, modulate_col: Color) -> StyleBoxTexture:
	# 20250420manaTabA-Sheet.png (252x32 -> 4 hojas de pergamino de 63x32 cada una)
	var at := AtlasTexture.new()
	at.atlas = HUD_TAB_A_TEX
	at.region = Rect2(tab_idx * 63, 0, 63, 32)
	var sb := StyleBoxTexture.new()
	sb.texture = at
	sb.modulate_color = modulate_col
	sb.texture_margin_left = 12
	sb.texture_margin_right = 12
	sb.texture_margin_top = 6
	sb.texture_margin_bottom = 6
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _create_diamond_icon_button(sheet_tex: Texture2D, tooltip: String) -> TextureButton:
	var tb := TextureButton.new()
	tb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tb.custom_minimum_size = Vector2(30, 30)
	tb.size = Vector2(30, 30)
	tb.tooltip_text = tooltip
	tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tb.self_modulate = Color(0.96, 0.88, 0.72, 0.90)

	var normal_at := AtlasTexture.new()
	normal_at.atlas = sheet_tex
	normal_at.region = Rect2(64, 0, 32, 32)
	tb.texture_normal = normal_at

	var hover_at := AtlasTexture.new()
	hover_at.atlas = sheet_tex
	hover_at.region = Rect2(0, 0, 32, 32)
	tb.texture_hover = hover_at

	var pressed_at := AtlasTexture.new()
	pressed_at.atlas = sheet_tex
	pressed_at.region = Rect2(64, 0, 32, 32)
	tb.texture_pressed = pressed_at

	return tb


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
