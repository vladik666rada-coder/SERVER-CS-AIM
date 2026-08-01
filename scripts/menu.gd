extends Control

const PORT := 7777

@onready var ip_edit: LineEdit = $Center/Panel/VBox/IpEdit
@onready var port_edit: LineEdit = $Center/Panel/VBox/PortEdit
@onready var nick_edit: LineEdit = $Center/Panel/VBox/NickEdit
@onready var status_label: Label = $Center/Panel/VBox/Status
@onready var host_btn: Button = $Center/Panel/VBox/HostBtn
@onready var offline_btn: Button = $Center/Panel/VBox/OfflineBtn
@onready var join_btn: Button = $Center/Panel/VBox/JoinBtn

func _ready() -> void:
	host_btn.pressed.connect(_on_host)
	offline_btn.pressed.connect(_on_offline)
	join_btn.pressed.connect(_on_join)
	var ip := _local_ip()
	ip_edit.text = ip if ip != "" else "127.0.0.1"
	status_label.text = ""

func _apply_nick() -> void:
	var nick := nick_edit.text.strip_edges()
	if nick == "":
		nick = "Игрок"
	G.nickname = nick

func _local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return ""

func _on_host() -> void:
	_apply_nick()
	var port := int(port_edit.text)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		status_label.text = "Ошибка сервера: %d" % err
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Сервер создан (порт %d). Ждём игрока..." % port
	_set_busy(true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_offline() -> void:
	_apply_nick()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_join() -> void:
	_apply_nick()
	var ip := ip_edit.text.strip_edges()
	var port := int(port_edit.text)
	if ip == "":
		status_label.text = "Введи IP"
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		status_label.text = "Ошибка подключения: %d" % err
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Подключение к %s:%d..." % [ip, port]
	_set_busy(true)
	multiplayer.connected_to_server.connect(_start_game)
	multiplayer.connection_failed.connect(_on_connection_failed)

func _on_peer_connected(_id: int) -> void:
	_start_game()

func _on_peer_disconnected(_id: int) -> void:
	status_label.text = "Игрок отключился"

func _on_connection_failed() -> void:
	status_label.text = "Не удалось подключиться"
	_set_busy(false)

func _set_busy(busy: bool) -> void:
	host_btn.disabled = busy
	join_btn.disabled = busy

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
