class_name Bullet
extends Area3D

const MAX_DISTANCE := 80.0

var velocity := Vector3.ZERO
var distance_traveled := 0.0

func _physics_process(delta: float) -> void:
	var step := velocity * delta
	var prev := global_position
	global_position = prev + step
	distance_traveled += step.length()

	if distance_traveled > MAX_DISTANCE:
		queue_free()
		return

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev, global_position)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		global_position = prev
		queue_free()

func setup(dir: Vector3) -> void:
	velocity = dir * 60.0
	if absf(dir.dot(Vector3.UP)) < 0.99:
		look_at(global_position + dir, Vector3.UP)
