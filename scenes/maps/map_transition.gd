class_name MapTransition
extends Area2D

## Guarda el nombre del Marker2D donde debe aparecer el jugador tras cargar la escena destino.
static var next_spawn_point: String = ""

## Escena del mapa al que se teletransporta el jugador al entrar en la zona.
@export_file("*.tscn") var target_map: String = ""

## Nombre del Marker2D dentro de "SpawnPoints" en el mapa destino.
@export var target_spawn: String = "Default"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Pastor":
		if not target_map.is_empty():
			next_spawn_point = target_spawn
			get_tree().call_deferred("change_scene_to_file", target_map)
