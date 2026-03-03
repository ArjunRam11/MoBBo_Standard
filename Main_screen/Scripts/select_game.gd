extends Control

@onready var logged_in_as    = $Logo/LoggedInAs
@onready var training_label  = $TrainingLabel
@onready var left_button     = $HandSelectionPopup/HBoxContainer/LeftButton
@onready var right_button    = $HandSelectionPopup/HBoxContainer/RightButton

# Preload all scenes at start (loads into memory for faster switching)
var random_reach_scene = preload("res://Games/random_reach/scenes/random_reach.tscn")
var flappy_scene = preload("res://Games/flappy_bird/Scenes/flappy_main.tscn")
var pingpong_scene = preload("res://Games/ping_pong/Scenes/PingPong.tscn")
var fruit_catcher = preload("res://Games/fruit_catcher/Scenes/Game/Game.tscn")
var assessment_scene = preload("res://Games/assessment/workspace.tscn")
var results_scene = preload("res://Results/scenes/user_progress.tscn")
var main_menu_scene = preload("res://Main_screen/Scenes/main.tscn")
var modescene = preload("res://Main_screen/Scenes/mode.tscn")
var cop_vis_scene = preload("res://Games/COP_visualise/COP_VIZ.tscn")



func _ready() -> void:
	logged_in_as.text = "Patient: " + PatientDB.current_patient_id
	var affected_hand = GlobalSignals.affected_hand

	if affected_hand == "Left":
		training_label.text = "Training for left hand"
		GlobalSignals.selected_training_hand = "Left"
	elif affected_hand == "Right":
		training_label.text = "Training for right hand"
		GlobalSignals.selected_training_hand = "Right"
	elif affected_hand == "Both":
		if GlobalSignals.selected_training_hand == "":
			$HandSelectionPopup.visible = true
			GlobalSignals.enable_game_buttons(false)
		else:
			training_label.text = "Training for %s hand" % GlobalSignals.selected_training_hand

func _process(delta: float) -> void:
	pass	
# ── UDP helper — notify Python to create Games/<game_name>/ folder ─────────────

func _notify_python_game_selected(game_name: String) -> void:
	"""
	Tell Python which game is about to start so it can pre-create
	the Games/<game_name>/PoseN/ folder structure before recording begins.
	"""
	GlobalSignals.current_game_name = game_name
	var sock = PacketPeerUDP.new()
	var cmd = {
		"type":      "game_selected",
		"game_name": game_name,
		"patient_id": PatientDB.current_patient_id,
		"timestamp": Time.get_ticks_msec()
	}
	if sock.set_dest_address("127.0.0.1", 9000) == OK:
		sock.put_packet(JSON.stringify(cmd).to_utf8_buffer())
		print("🎮 Game selected sent to Python: " + game_name)
	sock.close()


# ── Game buttons ───────────────────────────────────────────────────────────────

func _on_game_reach_pressed() -> void:
	_notify_python_game_selected("RandomReach")
	MusicManager.play_music("rr_bgm")
	get_tree().change_scene_to_packed(random_reach_scene)

func _on_game_flappy_pressed() -> void:
	_notify_python_game_selected("FlappyBird")
	MusicManager.play_music("ft_bgm")
	get_tree().change_scene_to_packed(flappy_scene)

func _on_game_pingpong_pressed() -> void:
	_notify_python_game_selected("PingPong")
	MusicManager.play_music("pp_bgm")
	get_tree().change_scene_to_packed(pingpong_scene)
	

func _on_assessment_pressed() -> void:
	get_tree().change_scene_to_packed(cop_vis_scene)
	
func _on_mode_pressed() -> void:
	get_tree().change_scene_to_packed(modescene)

func _on_results_pressed() -> void:
	get_tree().change_scene_to_packed(results_scene)


func _on_fruit_catcher_pressed() -> void:
	_notify_python_game_selected("FruitCatcher")
	MusicManager.play_music("fc_bgm")
	get_tree().change_scene_to_packed(fruit_catcher)


func _on_switch_3d_toggled(toggled_on: bool) -> void:
	GlobalSignals.selected_game_mode = "3D"
	get_tree().change_scene_to_file("res://Main_screen/Scenes/3d_games.tscn")


func _on_exit_pressed() -> void:
	GlobalScript._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	GlobalSignals.selected_training_hand = ""
	GlobalSignals.affected_hand = ""
	get_tree().quit()

func _on_logout_pressed() -> void:
	MusicManager.play_music("main")
	GlobalSignals.selected_training_hand = ""
	GlobalSignals.affected_hand = ""
	get_tree().change_scene_to_file("res://Main_screen/Scenes/main.tscn")


func _on_left_button_pressed() -> void:
	GlobalSignals.selected_training_hand = "Left"
	$HandSelectionPopup.hide()
	$TrainingLabel.text = "Training for Left Hand"
	GlobalSignals.enable_game_buttons(true)

func _on_right_button_pressed() -> void:
	GlobalSignals.selected_training_hand = "Right"
	$HandSelectionPopup.hide()
	$TrainingLabel.text = "Training for Right Hand"
	GlobalSignals.enable_game_buttons(true)
