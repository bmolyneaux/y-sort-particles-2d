@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type(
		"SortedParticles2D",
		"Node2D",
		preload("sorted_particles_2d.gd"),
		preload("icon.svg") if ResourceLoader.exists("res://addons/sorted_particles_2d/icon.svg") else null
	)


func _exit_tree() -> void:
	remove_custom_type("SortedParticles2D")
