class_name Trampoline
extends Area3D

const BOUNCE_VELOCITY := 14.0
const RECHARGE_TIME := 0.3

@onready var coil: Node3D = $Coil
@onready var pad: MeshInstance3D = $Pad

var timer := 0.0
var base_scale := 1.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	base_scale = coil.scale.y

func _physics_process(delta: float) -> void:
	if timer > 0.0:
		timer = maxf(timer - delta, 0.0)

func _on_body_entered(body: Node3D) -> void:
	if timer > 0.0:
		return
	if body is Player and body.velocity.y < 2.0:
		body.velocity.y = BOUNCE_VELOCITY
		timer = RECHARGE_TIME
		_bounce_anim()

func _bounce_anim() -> void:
	var tween := create_tween()
	tween.tween_property(coil, "scale:y", base_scale * 0.5, 0.08)
	tween.tween_property(coil, "scale:y", base_scale, 0.2)
	tween.parallel().tween_property(pad, "position:y", 0.12, 0.08)
	tween.parallel().tween_property(pad, "position:y", 0.0, 0.2)
