extends CharacterBody2D
## Survivor controller: CharacterBody2D physics + explicit state machine.
## Animation selection lives in _play_state(); gameplay never sets animations directly.

signal health_changed(value: int, max_value: int)
signal stamina_changed(value: float, max_value: float)
signal ammo_changed(in_mag: int, reserve: int)
signal state_changed(state_name: String)
signal died

enum State { IDLE, WALK, RUN, JUMP, FALL, CROUCH, MELEE, SHOOT, RELOAD, HURT, DEAD }

const STATE_ANIM := {
	State.IDLE: &"idle", State.WALK: &"walk", State.RUN: &"run",
	State.JUMP: &"jump", State.FALL: &"jump", State.CROUCH: &"crouch",
	State.MELEE: &"melee", State.SHOOT: &"shoot", State.RELOAD: &"idle",
	State.HURT: &"hurt", State.DEAD: &"hurt",
}

@export_group("Movement")
@export var walk_speed := 150.0
@export var run_speed := 260.0
@export var crouch_speed := 70.0
@export var acceleration := 1400.0
@export var friction := 1800.0
@export var air_control := 0.6
@export var jump_velocity := -520.0
@export var gravity := 1400.0
@export var max_fall_speed := 900.0
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12
@export_group("Survival")
@export var max_health := 100
@export var max_stamina := 100.0
@export var run_stamina_cost := 22.0
@export var stamina_regen := 14.0
@export_group("Combat")
@export var melee_damage := 25
@export var melee_cooldown := 0.45
@export var melee_hit_delay := 0.12
@export var gun_damage := 40
@export var gun_range := 800.0
@export var shoot_cooldown := 0.3
@export var mag_size := 7
@export var start_reserve := 21
@export var reload_time := 1.1

var health := 100
var stamina := 100.0
var ammo_in_mag := 7
var ammo_reserve := 21
var state: State = State.IDLE
var facing := 1

var _coyote := 0.0
var _jump_buffer := 0.0
var _action_timer := 0.0
var _melee_cd := 0.0
var _shoot_cd := 0.0
var _invuln := 0.0
var _bob_time := 0.0
var _crouched := false

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var body_shape: CollisionShape2D = $BodyShape
@onready var melee_area: Area2D = $MeleeHitbox
@onready var melee_shape: CollisionShape2D = $MeleeHitbox/Shape
@onready var muzzle: Node2D = $Muzzle
@onready var muzzle_flash: CanvasItem = $Muzzle/Flash
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	add_to_group("player")
	health = max_health
	stamina = max_stamina
	ammo_in_mag = mag_size
	ammo_reserve = start_reserve
	melee_area.monitoring = false
	muzzle_flash.visible = false
	_play_state()
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	ammo_changed.emit(ammo_in_mag, ammo_reserve)

func is_dead() -> bool:
	return state == State.DEAD

func is_crouching() -> bool:
	return _crouched

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		move_and_slide()
		return

	var axis := Input.get_axis(&"move_left", &"move_right")
	var locked := _action_timer > 0.0
	var wants_crouch := Input.is_action_pressed(&"crouch") and is_on_floor()
	var wants_run := Input.is_action_pressed(&"run") and axis != 0.0 and not wants_crouch and stamina > 1.0

	var speed := walk_speed
	if wants_crouch:
		speed = crouch_speed
	elif wants_run:
		speed = run_speed
	if locked and is_on_floor():
		speed *= 0.25
	var rate := acceleration if axis != 0.0 else friction
	if not is_on_floor():
		rate *= air_control
	velocity.x = move_toward(velocity.x, axis * speed, rate * delta)

	if wants_run and absf(velocity.x) > 10.0:
		stamina = maxf(stamina - run_stamina_cost * delta, 0.0)
	else:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
	stamina_changed.emit(stamina, max_stamina)

	if is_on_floor():
		_coyote = coyote_time
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer = jump_buffer_time
	if _jump_buffer > 0.0 and _coyote > 0.0 and not wants_crouch and not locked:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
	if Input.is_action_just_released(&"jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	if axis != 0.0 and not locked:
		facing = 1 if axis > 0.0 else -1
		_apply_facing()
	_set_crouched(wants_crouch)

	var was_airborne := not is_on_floor()
	move_and_slide()
	if was_airborne and is_on_floor():
		_on_landed()

	if Input.is_action_just_pressed(&"attack"):
		_try_melee()
	if Input.is_action_just_pressed(&"shoot"):
		_try_shoot()
	if Input.is_action_just_pressed(&"reload"):
		_try_reload()

	if _action_timer <= 0.0:
		_select_locomotion_state(wants_run)

func _process(delta: float) -> void:
	# Procedural step bob layered on the walk/run pose (the art has one pose per state).
	if state == State.WALK or state == State.RUN:
		_bob_time += delta * (9.0 if state == State.WALK else 14.0)
		sprite.position.y = -absf(sin(_bob_time)) * 3.0
		sprite.rotation = sin(_bob_time) * 0.025
	elif state != State.DEAD:
		sprite.position.y = lerpf(sprite.position.y, 0.0, 0.3)
		sprite.rotation = lerpf(sprite.rotation, 0.0, 0.3)
	camera.offset.x = lerpf(camera.offset.x, facing * 110.0, delta * 2.5)

func _tick_timers(delta: float) -> void:
	_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	_shoot_cd = maxf(_shoot_cd - delta, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	if _action_timer > 0.0:
		_action_timer -= delta
		if _action_timer <= 0.0 and state != State.DEAD:
			_action_timer = 0.0

func _select_locomotion_state(running: bool) -> void:
	var next := State.IDLE
	if not is_on_floor():
		next = State.JUMP if velocity.y < 0.0 else State.FALL
	elif _crouched:
		next = State.CROUCH
	elif absf(velocity.x) > 12.0:
		next = State.RUN if running else State.WALK
	_set_state(next)

func _set_state(next: State) -> void:
	if next == state:
		return
	state = next
	_play_state()
	state_changed.emit(State.keys()[state])

func _enter_action(next: State, duration: float) -> void:
	_action_timer = duration
	state = next
	_play_state()
	state_changed.emit(State.keys()[state])

func _play_state() -> void:
	var anim: StringName = STATE_ANIM[state]
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)

func _apply_facing() -> void:
	sprite.flip_h = facing < 0
	melee_shape.position.x = absf(melee_shape.position.x) * facing
	muzzle.position.x = absf(muzzle.position.x) * facing

func _set_crouched(value: bool) -> void:
	if value == _crouched:
		return
	_crouched = value
	var rect := body_shape.shape as RectangleShape2D
	rect.size.y = 92.0 if value else 136.0
	body_shape.position.y = -rect.size.y * 0.5

func _on_landed() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.42, 0.37), 0.06)
	tween.tween_property(sprite, "scale", Vector2(0.4, 0.4), 0.1)

func _try_melee() -> void:
	if _melee_cd > 0.0 or _action_timer > 0.0:
		return
	_melee_cd = melee_cooldown
	_enter_action(State.MELEE, 0.38)
	await get_tree().create_timer(melee_hit_delay, false).timeout
	if state != State.MELEE:
		return
	# Hitbox is live only inside this window; each body is hit at most once per swing.
	melee_area.monitoring = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	for body in melee_area.get_overlapping_bodies():
		if body.is_in_group("zombies") and body.has_method("take_damage"):
			body.call("take_damage", melee_damage, global_position)
	melee_area.monitoring = false
	get_tree().call_group("zombies", "hear_noise", global_position, 220.0)

func _try_shoot() -> void:
	if _shoot_cd > 0.0 or state == State.RELOAD or state == State.MELEE or state == State.DEAD:
		return
	if ammo_in_mag <= 0:
		_try_reload()
		return
	ammo_in_mag -= 1
	_shoot_cd = shoot_cooldown
	ammo_changed.emit(ammo_in_mag, ammo_reserve)
	_enter_action(State.SHOOT, 0.22)
	_flash_muzzle()
	var from := muzzle.global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(facing * gun_range, 0.0), 1 | 4, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider := hit["collider"] as Node
		if collider and collider.is_in_group("zombies") and collider.has_method("take_damage"):
			collider.call("take_damage", gun_damage, global_position)
	get_tree().call_group("zombies", "hear_noise", global_position, 900.0)
	_camera_kick(4.0)

func _try_reload() -> void:
	if state == State.RELOAD or state == State.DEAD or ammo_in_mag >= mag_size or ammo_reserve <= 0:
		return
	_enter_action(State.RELOAD, reload_time)
	await get_tree().create_timer(reload_time, false).timeout
	if state != State.RELOAD:
		return
	var moved := mini(mag_size - ammo_in_mag, ammo_reserve)
	ammo_in_mag += moved
	ammo_reserve -= moved
	ammo_changed.emit(ammo_in_mag, ammo_reserve)

func _flash_muzzle() -> void:
	muzzle_flash.visible = true
	await get_tree().create_timer(0.06, false).timeout
	muzzle_flash.visible = false

func _camera_kick(amount: float) -> void:
	var tween := create_tween()
	tween.tween_property(camera, "offset:y", -amount, 0.04)
	tween.tween_property(camera, "offset:y", 0.0, 0.08)

func take_damage(amount: int, from_position: Vector2) -> void:
	if state == State.DEAD or _invuln > 0.0:
		return
	health = maxi(health - amount, 0)
	_invuln = 0.5
	health_changed.emit(health, max_health)
	var push := 1.0 if global_position.x >= from_position.x else -1.0
	velocity = Vector2(push * 220.0, -140.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.35, 0.35), 0.05)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)
	if health <= 0:
		_die()
	else:
		_enter_action(State.HURT, 0.3)
		_camera_kick(6.0)

func _die() -> void:
	_action_timer = 0.0
	state = State.DEAD
	_play_state()
	state_changed.emit("DEAD")
	melee_area.monitoring = false
	var tween := create_tween()
	tween.tween_property(sprite, "rotation", -1.45 * facing, 0.35).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sprite, "position:y", 12.0, 0.35)
	died.emit()
