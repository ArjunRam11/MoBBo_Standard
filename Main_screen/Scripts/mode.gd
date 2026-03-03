extends Node2D
func _ready() -> void:
	pass


func _on_2d_games_pressed() -> void:
	if not CoPManager.is_configured():
		_popup_board_setup_required()
		return
	GlobalSignals.selected_game_mode = "2D"
	print("2D")
	get_tree().change_scene_to_file("res://Main_screen/Scenes/select_game.tscn")
	
	
func _on_Brd_setup_pressed() -> void:
	print("boardsetup pressed")
	GlobalSignals.selected_game_mode = "BRDSETUP"
	get_tree().change_scene_to_file("res://Main_screen/Scenes/Boardsetup_IP.tscn")

   
func _on_3d_games_pressed() -> void:
	if not CoPManager.is_configured():
		_popup_board_setup_required()
		return
	GlobalSignals.selected_game_mode = "3D"
	get_tree().change_scene_to_file("res://Main_screen/Scenes/3d_games.tscn")

func _popup_board_setup_required() -> void:
	var popup = AcceptDialog.new()
	popup.title = "Board Setup Required"
	popup.dialog_text = "Please configure the balance boards first before playing games."
	popup.ok_button_text = "Go to Board Setup"
	popup.cancel_button_text = "Cancel"
	get_tree().current_scene.add_child(popup)
	popup.popup_centered()
	popup.visibility_changed.connect(func():
		if not popup.visible:
			popup.queue_free()
	)
	popup.canceled.connect(func():
		popup.queue_free()
	)
	popup.confirmed.connect(func():
		popup.queue_free()
		_on_Brd_setup_pressed()
	)


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Main_screen/Scenes/main.tscn")


func _on_board_setup_assessment_pressed() -> void:
	pass # Replace with function body.
