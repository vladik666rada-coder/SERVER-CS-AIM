extends Node3D

func _ready() -> void:
	var port := 7777
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		port = env_port.to_int()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)
	if err != OK:
		push_error("Server failed on port %d: %d" % [port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	print("Dedicated server listening on port %d" % port)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")
