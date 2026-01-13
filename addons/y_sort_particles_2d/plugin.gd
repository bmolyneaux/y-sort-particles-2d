@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type(
		"YSortParticles2D",
		"Node2D",
		preload("y_sort_particles_2d.gd"),
		preload("icon.svg") if ResourceLoader.exists("res://addons/y_sort_particles_2d/icon.svg") else null
	)


func _exit_tree() -> void:
	remove_custom_type("YSortParticles2D")
