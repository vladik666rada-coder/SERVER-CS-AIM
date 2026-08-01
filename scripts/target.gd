class_name Target
extends StaticBody3D

signal hit(value: int)

func take_hit() -> void:
	hit.emit(100)
	queue_free()
