extends Node

enum GameState { PLAYING, PAUSED, GAME_OVER }

signal game_state_changed(new_state: GameState)

var current_state: GameState = GameState.PLAYING

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input_actions()

func _setup_input_actions() -> void:
	# Z : 기본공격
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_Z
		InputMap.action_add_event("attack", e)

	# X : 특수공격 (차지, 홀드)
	if not InputMap.has_action("special_attack"):
		InputMap.add_action("special_attack")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_X
		InputMap.action_add_event("special_attack", e)

	# Space : 대쉬
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_SPACE
		InputMap.action_add_event("dash", e)

	# WASD를 기본 ui_* 방향키에 추가
	var wasd := {
		"ui_left":  KEY_A,
		"ui_right": KEY_D,
		"ui_up":    KEY_W,
		"ui_down":  KEY_S,
	}
	for action: String in wasd:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = wasd[action]
		InputMap.action_add_event(action, key_event)

func set_state(new_state: GameState) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	game_state_changed.emit(new_state)
	get_tree().paused = (new_state == GameState.PAUSED)

func game_over() -> void:
	set_state(GameState.GAME_OVER)
