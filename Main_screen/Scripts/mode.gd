extends Node2D
func _ready() -> void:
	# By the time mode selection loads, Python's compute_COP is running.
	# Send patient ID now so it arrives when port 9000 is actually listening.
	if PatientDB.current_patient_id != "":
		await get_tree().create_timer(0.5).timeout
		_send_patient_to_python(PatientDB.current_patient_id)

func _send_patient_to_python(patient_id: String) -> void:
	var command_socket = PacketPeerUDP.new()
	var command = {
		"type": "set_patient",
		"patient_id": patient_id,
		"timestamp": Time.get_ticks_msec()
	}
	if command_socket.set_dest_address("127.0.0.1", 9000) == OK:
		command_socket.put_packet(JSON.stringify(command).to_utf8_buffer())
		print("✅ Patient sent to Python from mode screen: " + patient_id)
	command_socket.close()


func _on_2d_games_pressed() -> void:
	# Set global flag for 2D mode before transitioning
	GlobalSignals.selected_game_mode = "2D"
	print("2D")
	get_tree().change_scene_to_file("res://Main_screen/Scenes/select_game.tscn")
	
	
func _on_Brd_setup_pressed() -> void:
	# Set global flag for 2D mode before transitioning
	print("boardsetup pressed")
	GlobalSignals.selected_game_mode = "BRDSETUP"
	get_tree().change_scene_to_file("res://Games/BoardViz/board_setup.tscn")

   
func _on_3d_games_pressed() -> void:
	# Set global flag for 3D mode before transitioning  
	GlobalSignals.selected_game_mode = "3D"
	get_tree().change_scene_to_file("res://Main_screen/Scenes/3d_games.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Main_screen/Scenes/main.tscn")


func _on_board_setup_assessment_pressed() -> void:
	pass # Replace with function body.
