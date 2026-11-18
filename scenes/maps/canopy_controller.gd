extends TileMapLayer

func _process(_delta: float) -> void:
	if material is ShaderMaterial:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			(material as ShaderMaterial).set_shader_parameter("player_world_pos", player.global_position + Vector2(0.0, -10.0))
