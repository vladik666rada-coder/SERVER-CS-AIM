extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const TARGET_SCENE := preload("res://scenes/target.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const DEATH_SCENE := preload("res://scenes/death_effect.tscn")

const PLAYER_MAX_HP := 100
const PLAYER_DAMAGE := 34
const RESPAWN_DELAY := 2.5

const SPAWN_POINTS := [
	Vector3(0, 0.2, 0.3),
	Vector3(-5, 0.2, 0.3),
]

var scores := {}
var hp := {}
var is_dead := {}
var spawn_idx := {}

@onready var players: Node3D = $Players
@onready var targets: Node3D = $Targets
@onready var bullets: Node3D = $Bullets

func _ready() -> void:
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if not multiplayer.has_multiplayer_peer() or DisplayServer.get_name() != "headless":
			_spawn_player(1, SPAWN_POINTS[0])
		call_deferred("_spawn_initial_targets")
	else:
		client_ready.rpc_id(1)

func _spawn_point_for(id: int) -> Vector3:
	var idx: int = spawn_idx.get(id, players.get_child_count())
	spawn_idx[id] = idx
	return SPAWN_POINTS[idx % SPAWN_POINTS.size()]

func _on_peer_connected(id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	var p := players.get_node_or_null(str(id))
	if p != null:
		p.queue_free()
	scores.erase(id)
	hp.erase(id)
	is_dead.erase(id)
	_broadcast_state()

@rpc("any_peer", "call_remote", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.get_node_or_null(str(id)) == null:
		_spawn_player(id, _spawn_point_for(id))
		for p in players.get_children():
			var pid := int(p.name)
			if pid != id:
				_spawn_player_rpc.rpc_id(id, pid, p.global_position)
				p.rpc_id(id, "_sync_nick", p.nick)
		_send_targets_to(id)
	_broadcast_state()

func _spawn_player(id: int, pos: Vector3) -> void:
	spawn_idx[id] = players.get_child_count()
	_spawn_player_rpc(id, pos)
	if multiplayer.has_multiplayer_peer():
		_spawn_player_rpc.rpc(id, pos)
	scores[id] = 0
	hp[id] = PLAYER_MAX_HP
	is_dead[id] = false
	_broadcast_state()

@rpc("authority", "call_remote", "reliable")
func _spawn_player_rpc(id: int, pos: Vector3) -> void:
	if players.get_node_or_null(str(id)) != null:
		return
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	players.add_child(p)
	p.global_position = pos

func _spawn_initial_targets() -> void:
	for i in 4:
		_spawn_target()

func _spawn_target() -> void:
	if not multiplayer.is_server():
		return
	var angle := randf_range(0.0, TAU)
	var radius := randf_range(4.0, 12.0)
	var pos: Vector3 = Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
	_spawn_target_rpc(pos)
	if multiplayer.has_multiplayer_peer():
		_spawn_target_rpc.rpc(pos)

@rpc("authority", "call_remote", "reliable")
func _spawn_target_rpc(pos: Vector3) -> void:
	var t := TARGET_SCENE.instantiate()
	t.name = "Target%d" % targets.get_child_count()
	targets.add_child(t)
	t.global_position = pos

func _send_targets_to(id: int) -> void:
	for t in targets.get_children():
		_spawn_target_rpc.rpc_id(id, t.global_position)

func _remove_target(node: Node3D) -> void:
	var name: String = str(node.name)
	_remove_target_rpc(name)
	if multiplayer.has_multiplayer_peer():
		_remove_target_rpc.rpc(name)

@rpc("authority", "call_remote", "reliable")
func _remove_target_rpc(tname: String) -> void:
	var t := targets.get_node_or_null(tname)
	if t != null:
		t.queue_free()

@rpc("any_peer", "call_remote", "unreliable")
func shoot(from: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var shooter := multiplayer.get_remote_sender_id()
	_resolve_shot(shooter, from, dir)

func _resolve_shot(shooter: int, from: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var to := from + dir * 120.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var shooter_node := players.get_node_or_null(str(shooter))
	if shooter_node != null:
		query.exclude = [shooter_node]
	var hit := space.intersect_ray(query)
	var aim: Vector3 = hit.get("position", to)

	_spawn_bullet(from, dir)

	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is Target:
		scores[shooter] = scores.get(shooter, 0) + 100
		_broadcast_state()
		_play_target_effect(collider as Node3D)
		_remove_target(collider as Node3D)
		get_tree().create_timer(0.9).timeout.connect(_spawn_target)
	elif collider is Player:
		var vid := int((collider as Node).name)
		if vid == shooter:
			return
		_damage_player(vid, shooter)

func _damage_player(vid: int, attacker: int) -> void:
	if is_dead.get(vid, false):
		return
	hp[vid] = maxi(hp.get(vid, PLAYER_MAX_HP) - PLAYER_DAMAGE, 0)
	if hp[vid] <= 0:
		is_dead[vid] = true
		_broadcast_state()
		_play_death_effect(vid)
		_hide_player(vid)
		if multiplayer.has_multiplayer_peer():
			_you_died.rpc_id(vid, attacker)
		await get_tree().create_timer(RESPAWN_DELAY).timeout
		if not is_inside_tree():
			return
		hp[vid] = PLAYER_MAX_HP
		is_dead[vid] = false
		_respawn_player(vid)
	else:
		_broadcast_state()

@rpc("authority", "call_remote", "reliable")
func _you_died(killer: int) -> void:
	var lbl := get_node_or_null("UI/DeathLabel") as Label
	if lbl != null:
		lbl.text = "ТЫ УМЕР"
		lbl.visible = true
		var hide := func() -> void:
			lbl.visible = false
		get_tree().create_timer(2.0).timeout.connect(hide)

func _hide_player(vid: int) -> void:
	_set_player_visible_rpc(vid, false)
	if multiplayer.has_multiplayer_peer():
		_set_player_visible_rpc.rpc(vid, false)

@rpc("authority", "call_remote", "reliable")
func _set_player_visible_rpc(vid: int, visible: bool) -> void:
	var p := players.get_node_or_null(str(vid))
	if p != null:
		p.visible = visible

func _play_death_effect(vid: int) -> void:
	var p := players.get_node_or_null(str(vid))
	var pos: Vector3 = p.global_position if p != null else SPAWN_POINTS[0]
	_spawn_death_effect(pos)
	if multiplayer.has_multiplayer_peer():
		_spawn_death_effect.rpc(pos)

@rpc("authority", "call_remote", "reliable")
func _spawn_death_effect(pos: Vector3) -> void:
	var e: Node3D = DEATH_SCENE.instantiate()
	add_child(e)
	e.global_position = pos
	get_tree().create_timer(3.0).timeout.connect(e.queue_free)

func _play_target_effect(target_node: Node3D) -> void:
	var pos: Vector3 = target_node.global_position
	_spawn_death_effect(pos)
	if multiplayer.has_multiplayer_peer():
		_spawn_death_effect.rpc(pos)

func _respawn_player(id: int) -> void:
	var idx: int = spawn_idx.get(id, 0)
	var pos: Vector3 = SPAWN_POINTS[idx % SPAWN_POINTS.size()]
	_respawn_player_rpc(id, pos)
	if multiplayer.has_multiplayer_peer():
		_respawn_player_rpc.rpc(id, pos)
	_broadcast_state()

@rpc("authority", "call_remote", "reliable")
func _respawn_player_rpc(id: int, pos: Vector3) -> void:
	var p := players.get_node_or_null(str(id))
	if p != null:
		p.visible = true
		p.global_position = pos

func _spawn_bullet(from: Vector3, dir: Vector3) -> void:
	var b := BULLET_SCENE.instantiate()
	bullets.add_child(b)
	b.global_position = from
	b.setup(dir)
	if multiplayer.has_multiplayer_peer():
		_spawn_bullet_rpc.rpc(from, dir)

@rpc("authority", "call_remote", "unreliable")
func _spawn_bullet_rpc(from: Vector3, dir: Vector3) -> void:
	var b := BULLET_SCENE.instantiate()
	bullets.add_child(b)
	b.global_position = from
	b.setup(dir)

func _broadcast_state() -> void:
	if not multiplayer.is_server():
		return
	_update_ui(scores, hp, is_dead)
	if multiplayer.has_multiplayer_peer():
		_update_ui.rpc(scores, hp, is_dead)

@rpc("authority", "call_remote", "reliable")
func _update_ui(s: Dictionary, h: Dictionary, d: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	var other_id := -1
	for p in players.get_children():
		var pid := int(p.name)
		if pid != my_id:
			other_id = pid
			break
	var score_label := get_node_or_null("UI/ScoreLabel")
	var hp_label := get_node_or_null("UI/HealthLabel")
	if score_label != null:
		score_label.text = "Вы: %d   Соперник: %d" % [s.get(my_id, 0), s.get(other_id, 0)]
	if hp_label != null:
		hp_label.text = "HP: %d" % h.get(my_id, PLAYER_MAX_HP)
