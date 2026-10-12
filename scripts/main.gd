extends Node2D
## Level root: wires HUD to the player, tracks the objective, keeps touch controls
## pinned to the screen edges on any aspect ratio, and releases inputs on focus loss.

const WORLD_WIDTH := 1577
const TOUCH_ACTIONS := [&"move_left", &"move_right", &"jump", &"crouch", &"run", &"attack", &"shoot", &"reload"]

@onready var player: CharacterBody2D = $Player
@onready var health_bar: ProgressBar = $HUD/Root/Stats/HealthBar
@onready var stamina_bar: ProgressBar = $HUD/Root/Stats/StaminaBar
@onready var ammo_label: Label = $HUD/Root/Ammo
@onready var objective_label: Label = $HUD/Root/Objective
@onready var death_panel: Control = $HUD/Root/DeathPanel
@onready var right_controls: Node2D = $Touch/Right

var _zombies_total := 0
var _zombies_killed := 0

func _ready() -> void:
	player.connect("health_changed", _on_health_changed)
	player.connect("stamina_changed", _on_stamina_changed)
	player.connect("ammo_changed", _on_ammo_changed)
	player.connect("died", _on_player_died)
	for zombie in get_tree().get_nodes_in_group("zombies"):
		_zombies_total += 1
		zombie.connect("died", _on_zombie_died)
	_update_objective()
	death_panel.visible = false
	get_viewport().size_changed.connect(_layout_touch)
	_layout_touch()

func _on_health_changed(value: int, max_value: int) -> void:
	health_bar.max_value = max_value
	health_bar.value = value

func _on_stamina_changed(value: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value

func _on_ammo_changed(in_mag: int, reserve: int) -> void:
	ammo_label.text = "AMMO  %d / %d" % [in_mag, reserve]

func _layout_touch() -> void:
	var width := get_viewport().get_visible_rect().size.x
	right_controls.position.x = width - 1280.0

func _on_zombie_died(_zombie: Node) -> void:
	_zombies_killed += 1
	_update_objective()

func _update_objective() -> void:
	if _zombies_killed >= _zombies_total:
		objective_label.text = "WARD CLEARED  •  head for the metro exit"
	else:
		objective_label.text = "CLEAR THE WARD  %d / %d infected" % [_zombies_killed, _zombies_total]

func _on_player_died() -> void:
	death_panel.visible = true
	await get_tree().create_timer(3.0).timeout
	get_tree().reload_current_scene()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		for action in TOUCH_ACTIONS:
			Input.action_release(action)
