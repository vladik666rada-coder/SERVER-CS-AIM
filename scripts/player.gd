class_name Player
extends CharacterBody3D

const SPEED := 6.0
const SPRINT_SPEED := 10.0
const JUMP_VELOCITY := 4.5
const GRAVITY := 12.0
const MOUSE_SENS := 0.0025
const RECOIL_SPEED := 8.0

const MAG_SIZE := 12
const AK_MAG_SIZE := 30
const RELOAD_DURATION := 1.5
const STEP_INTERVAL := 0.35
const SYNC_INTERVAL := 0.06

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var pistol: Node3D = $Head/Pistol
@onready var muzzle_flash: OmniLight3D = $Head/Pistol/MuzzleFlash
@onready var shoot_sound: AudioStreamPlayer3D = $ShootSound
@onready var walk_sound: AudioStreamPlayer3D = $WalkSound
@onready var gun: Node3D = $Head/Pistol/Gun
@onready var knife: Node3D = $Head/Knife
@onready var ak47: Node3D = $Head/AK47
@onready var ak_muzzle_flash: OmniLight3D = $Head/AK47/AKMuzzleFlash
@onready var body: MeshInstance3D = $Body
@onready var name_label: Label3D = $NameLabel
@onready var crosshair: Control = get_tree().current_scene.get_node_or_null("UI/Crosshair") as Control

enum Weapon { GUN, KNIFE, AK }
var current_weapon := Weapon.GUN

var cooldown := 0.0
var recoil := 0.0
var ammo: Dictionary = {Weapon.GUN: MAG_SIZE, Weapon.AK: AK_MAG_SIZE}
var is_reloading := false
var reload_time := 0.0
var step_timer := 0.0
var idle_time := 0.0

var gun_base_pos := Vector3.ZERO
var gun_base_rot := Vector3.ZERO
var knife_base_pos := Vector3.ZERO
var knife_base_rot := Vector3.ZERO
var ak_base_pos := Vector3.ZERO
var ak_base_rot := Vector3.ZERO

var sync_timer := 0.0
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var has_target := false
var is_moving := false
var last_remote_pos := Vector3.ZERO
var target_reloading := false
var nick := "Игрок"

func _ready() -> void:
	gun_base_pos = gun.position
	gun_base_rot = gun.rotation
	knife_base_pos = knife.position
	knife_base_rot = knife.rotation
	ak_base_pos = ak47.position
	ak_base_rot = ak47.rotation
	name_label.text = "Игрок %s" % name
	if _am_authority() and G.nickname != "" and G.nickname != "Игрок":
		nick = G.nickname
		name_label.text = nick
	if _am_authority() and multiplayer.has_multiplayer_peer():
		rpc("_sync_nick", nick)

	if not _am_authority():
		_setup_remote()
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true
	body.visible = false
	name_label.visible = false
	_apply_weapon_visibility()
	_update_ammo_label()

func _setup_remote() -> void:
	camera.current = false
	body.visible = true
	name_label.visible = true
	_apply_weapon_visibility()

func _am_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var peer := multiplayer.multiplayer_peer
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return is_multiplayer_authority()

@rpc("any_peer", "call_remote", "reliable")
func _sync_nick(nick_text: String) -> void:
	if _am_authority():
		return
	nick = nick_text
	name_label.text = nick_text

func _input(event: InputEvent) -> void:
	if not _am_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

func _unhandled_input(event: InputEvent) -> void:
	if not _am_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("weapon_1"):
		_switch_weapon(Weapon.GUN)
	if event.is_action_pressed("weapon_2"):
		_switch_weapon(Weapon.KNIFE)
	if event.is_action_pressed("weapon_3"):
		_switch_weapon(Weapon.AK)

func _physics_process(delta: float) -> void:
	if not _am_authority():
		if multiplayer.has_multiplayer_peer():
			_interpolate_remote(delta)
		_update_weapon_anim(delta, false)
		return

	cooldown = maxf(cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): dir.z += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY
	dir = dir.normalized()

	var speed := SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else SPEED

	var basis := global_transform.basis
	velocity.x = basis.x.x * dir.x * speed + basis.z.x * dir.z * speed
	velocity.z = basis.x.z * dir.x * speed + basis.z.z * dir.z * speed
	move_and_slide()

	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	if moving and is_on_floor():
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = STEP_INTERVAL
			walk_sound.play()
	else:
		step_timer = 0.0

	if Input.is_key_pressed(KEY_R) and current_weapon != Weapon.KNIFE and not is_reloading and _current_ammo() < _mag_size():
		_reload()

	recoil = lerpf(recoil, 0.0, RECOIL_SPEED * delta)

	_update_weapon_anim(delta, moving)

	if (current_weapon == Weapon.GUN or current_weapon == Weapon.AK) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cooldown <= 0.0 and not is_reloading:
		_shoot()

	sync_timer -= delta
	if sync_timer <= 0.0:
		sync_timer = SYNC_INTERVAL
		rpc("_sync_transform", global_position, global_rotation.y, head.rotation.x, is_reloading)

func _update_weapon_anim(delta: float, moving: bool) -> void:
	idle_time += delta
	var sway := 0.012
	if moving:
		sway = 0.02

	if is_reloading:
		reload_time += delta
		var t := clampf(reload_time / RELOAD_DURATION, 0.0, 1.0)
		if current_weapon == Weapon.AK:
			ak47.position = ak_base_pos + Vector3(0.0, -0.22 * sin(t * PI), 0.18 * sin(t * PI))
			ak47.rotation = ak_base_rot + Vector3(0.35 * sin(t * PI), 0.0, 0.0)
		else:
			gun.position = gun_base_pos + Vector3(0.0, -0.22 * sin(t * PI), 0.18 * sin(t * PI))
			gun.rotation = gun_base_rot + Vector3(0.35 * sin(t * PI), 0.0, 0.0)
		if t >= 1.0:
			_finish_reload()
	elif current_weapon == Weapon.KNIFE:
		knife.position = knife_base_pos + Vector3(
			sin(idle_time * 1.6) * sway,
			sin(idle_time * 3.2) * sway * 0.6,
			sin(idle_time * 1.6) * sway * 0.3)
		knife.rotation = knife_base_rot + Vector3(
			sin(idle_time * 3.2) * 0.004,
			0.0,
			cos(idle_time * 1.6) * 0.006)
	else:
		pistol.position = Vector3(0.3 + recoil * 0.03, -0.25 + recoil * 0.04, -0.5 + recoil * 0.1)
		pistol.rotation.x = -recoil * 0.15
		if current_weapon == Weapon.AK:
			ak47.position = ak_base_pos + Vector3(
				sin(idle_time * 1.6) * sway,
				sin(idle_time * 3.2) * sway * 0.6,
				sin(idle_time * 1.6) * sway * 0.3)
			ak47.rotation = ak_base_rot + Vector3(
				sin(idle_time * 3.2) * 0.004,
				0.0,
				cos(idle_time * 1.6) * 0.006)
		else:
			gun.position = gun_base_pos + Vector3(
				sin(idle_time * 1.6) * sway,
				sin(idle_time * 3.2) * sway * 0.6,
				sin(idle_time * 1.6) * sway * 0.3)
			gun.rotation = gun_base_rot + Vector3(
				sin(idle_time * 3.2) * 0.004,
				0.0,
				cos(idle_time * 1.6) * 0.006)

func _interpolate_remote(delta: float) -> void:
	if not has_target:
		return
	var k := 1.0 - exp(-14.0 * delta)
	global_position = global_position.lerp(target_pos, k)
	global_rotation.y = lerp_angle(global_rotation.y, target_yaw, k)
	head.rotation.x = lerp_angle(head.rotation.x, target_pitch, k)
	is_moving = global_position.distance_to(last_remote_pos) > 0.02
	last_remote_pos = global_position
	if target_reloading:
		if not is_reloading:
			reload_time = 0.0
			is_reloading = true
	elif is_reloading:
		_finish_reload()

@rpc("any_peer", "call_remote", "unreliable")
func _sync_transform(pos: Vector3, yaw: float, pitch: float, reloading: bool) -> void:
	if _am_authority():
		return
	target_pos = pos
	target_yaw = yaw
	target_pitch = pitch
	target_reloading = reloading
	has_target = true

func _shoot() -> void:
	cooldown = 0.15
	recoil = 1.0
	shoot_sound.play()

	var from := camera.global_position
	var dir := -camera.global_transform.basis.z

	var main := get_tree().current_scene
	if multiplayer.is_server():
		main._resolve_shot(multiplayer.get_unique_id(), from, dir)
	else:
		main.shoot.rpc_id(1, from, dir)

	var flash: OmniLight3D = ak_muzzle_flash if current_weapon == Weapon.AK else muzzle_flash
	flash.light_energy = 3.0
	flash.get_node("Mesh").visible = true
	get_tree().create_timer(0.05).timeout.connect(func() -> void:
		flash.light_energy = 0.0
		flash.get_node("Mesh").visible = false)

	ammo[current_weapon] = int(ammo[current_weapon]) - 1
	_update_ammo_label()
	if _current_ammo() <= 0:
		_reload()

func _mag_size() -> int:
	return AK_MAG_SIZE if current_weapon == Weapon.AK else MAG_SIZE

func _current_ammo() -> int:
	return int(ammo.get(current_weapon, MAG_SIZE))

func _reload() -> void:
	is_reloading = true
	reload_time = 0.0
	if _am_authority():
		rpc("_sync_reload", true)
		_update_ammo_label()

func _finish_reload() -> void:
	is_reloading = false
	ammo[current_weapon] = _mag_size()
	if current_weapon == Weapon.AK:
		ak47.position = ak_base_pos
		ak47.rotation = ak_base_rot
	else:
		gun.position = gun_base_pos
		gun.rotation = gun_base_rot
	if _am_authority():
		rpc("_sync_reload", false)
		_update_ammo_label()

@rpc("any_peer", "call_remote", "reliable")
func _sync_reload(active: bool) -> void:
	if _am_authority():
		return
	is_reloading = active
	reload_time = 0.0

func _switch_weapon(weapon: Weapon) -> void:
	if current_weapon == weapon:
		return
	if is_reloading:
		_finish_reload()
	current_weapon = weapon
	_apply_weapon_visibility()
	rpc("_sync_weapon", weapon)
	if weapon == Weapon.KNIFE:
		pistol.position = Vector3(0.3, -0.25, -0.5)
		pistol.rotation.x = 0.0
		gun.position = gun_base_pos
		gun.rotation = gun_base_rot
		ak47.position = ak_base_pos
		ak47.rotation = ak_base_rot
	_update_ammo_label()

func _apply_weapon_visibility() -> void:
	pistol.visible = current_weapon == Weapon.GUN
	knife.visible = current_weapon == Weapon.KNIFE
	ak47.visible = current_weapon == Weapon.AK
	gun.visible = current_weapon == Weapon.GUN

@rpc("any_peer", "call_remote", "reliable")
func _sync_weapon(weapon: int) -> void:
	if _am_authority():
		return
	current_weapon = weapon as Weapon
	_apply_weapon_visibility()

func _update_ammo_label() -> void:
	var label: Label = null
	var scene := get_tree().current_scene
	if scene != null:
		label = scene.get_node_or_null("UI/AmmoLabel") as Label
	if label == null:
		label = get_tree().get_first_node_in_group("hud_ammo")
	if label == null:
		return
	if current_weapon == Weapon.KNIFE:
		label.text = ""
		if crosshair != null:
			crosshair.visible = false
		return
	if crosshair != null:
		crosshair.visible = true
	var mag := _mag_size()
	if is_reloading:
		label.text = "Ammo: 0/%d  (перезарядка...)" % mag
	else:
		label.text = "Ammo: %d/%d  [R - перезарядка]" % [_current_ammo(), mag]
