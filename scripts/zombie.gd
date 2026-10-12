extends CharacterBody2D
## Zombie AI: idle -> patrol -> investigate (noise) -> chase -> attack, plus hurt and death.
## Each zombie type uses its own single-pose sprite; motion is procedural (sway/lunge),
## and speed drives the sway so it never "slides" with a frozen walk.

signal died(zombie: Node)

enum State { IDLE, PATROL, INVESTIGATE, CHASE, ATTACK, HURT, DEAD }

@export var display_name := "Walker"
@export var sprite_texture: Texture2D
@export var body_size := Vector2(46, 136)
@export var max_health := 80
@export var patrol_speed := 30.0
@export var chase_speed := 62.0
@export var detection_range := 380.0
@export var attack_range := 58.0
@export var attack_damage := 10
@export var attack_cooldown := 1.4
@export var attack_windup := 0.35
@export var patrol_distance := 140.0
@export var is_screamer := false
@export var scream_radius := 750.0
@export var gravity := 1400.0

var health := 80
var state: State = State.IDLE
var facing := -1
var _home_x := 0.0
var _target_x := 0.0
var _state_timer := 0.0
var _attack_cd := 0.0
var _attack_hit_done := false
var _sway := 0.0
var _has_screamed := false

@onready var sprite: Sprite2D = $Sprite
@onready var body_shape: CollisionShape2D = $BodyShape

func _ready() -> void:
	add_to_group("zombies")
	health = max_health
	_home_x = global_position.x
	if sprite_texture:
		sprite.texture = sprite_texture
	if sprite.texture:
		sprite.offset = Vector2(0.0, -sprite.texture.get_height() * 0.5)
	var rect := body_shape.shape as RectangleShape2D
	rect.size = body_size
	body_shape.position = Vector2(0.0, -body_size.y * 0.5)
	_enter(State.IDLE, randf_range(0.5, 2.0))
	_apply_facing()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_state_timer -= delta
	var player := _get_player()

	match state:
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			if _state_timer <= 0.0:
				_enter(State.CHASE if player else State.IDLE, 0.0)
		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
			_update_attack(player)
		_:
			if player and _can_see(player):
				if state != State.CHASE:
					_enter(State.CHASE, 0.0)
			_update_movement(player, delta)

	move_and_slide()
	if is_on_wall() and (state == State.PATROL or state == State.INVESTIGATE):
		_enter(State.IDLE, 1.0)

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	var moving := absf(velocity.x) > 4.0
	if moving:
		_sway += delta * clampf(absf(velocity.x) / 12.0, 3.0, 16.0)
		sprite.rotation = sin(_sway) * 0.05
		sprite.position.y = -absf(sin(_sway)) * 2.5
	else:
		sprite.rotation = lerpf(sprite.rotation, sin(Time.get_ticks_msec() * 0.002) * 0.015, 0.1)
		sprite.position.y = lerpf(sprite.position.y, 0.0, 0.2)

func _update_movement(player: Node2D, _delta: float) -> void:
	var dir := 0.0
	var speed := patrol_speed
	match state:
		State.IDLE:
			if _state_timer <= 0.0:
				_target_x = _home_x + randf_range(-patrol_distance, patrol_distance)
				_enter(State.PATROL, 6.0)
		State.PATROL, State.INVESTIGATE:
			var dx := _target_x - global_position.x
			if absf(dx) < 10.0 or _state_timer <= 0.0:
				_enter(State.IDLE, randf_range(1.0, 2.5))
			else:
				dir = signf(dx)
				if state == State.INVESTIGATE:
					speed = patrol_speed * 1.6
		State.CHASE:
			if player == null:
				_enter(State.IDLE, 1.0)
			else:
				var offset := player.global_position - global_position
				_target_x = player.global_position.x
				if offset.length() > detection_range * 1.5:
					_enter(State.INVESTIGATE, 5.0)
				elif absf(offset.x) <= attack_range and absf(offset.y) < 70.0:
					if _attack_cd <= 0.0:
						_start_attack()
				else:
					dir = signf(offset.x)
					speed = chase_speed
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
	velocity.x = move_toward(velocity.x, dir * speed, 600.0 * get_physics_process_delta_time())

func _start_attack() -> void:
	_attack_hit_done = false
	_enter(State.ATTACK, attack_windup + 0.3)
	var tween := create_tween()
	tween.tween_property(sprite, "position:x", 10.0 * facing, attack_windup).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "position:x", 0.0, 0.2)

func _update_attack(player: Node2D) -> void:
	var elapsed := (attack_windup + 0.3) - _state_timer
	if not _attack_hit_done and elapsed >= attack_windup:
		_attack_hit_done = true
		_attack_cd = attack_cooldown
		if player and absf(player.global_position.x - global_position.x) <= attack_range + 12.0 \
				and absf(player.global_position.y - global_position.y) < 70.0 and _clear_line(player):
			player.call("take_damage", attack_damage, global_position)
	if _state_timer <= 0.0:
		_enter(State.CHASE, 0.0)

func _get_player() -> Node2D:
	var node := get_tree().get_first_node_in_group("player")
	if node == null or not is_instance_valid(node) or node.call("is_dead"):
		return null
	return node as Node2D

func _can_see(player: Node2D) -> bool:
	var range_mult := 0.55 if player.call("is_crouching") else 1.0
	var offset := player.global_position - global_position
	if offset.length() > detection_range * range_mult or absf(offset.y) > 120.0:
		return false
	return _clear_line(player)

func _clear_line(player: Node2D) -> bool:
	var eye := global_position + Vector2(0.0, -body_size.y * 0.7)
	var target := player.global_position + Vector2(0.0, -70.0)
	var query := PhysicsRayQueryParameters2D.create(eye, target, 1, [get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func hear_noise(source: Vector2, radius: float) -> void:
	if state == State.DEAD or state == State.CHASE or state == State.ATTACK:
		return
	if global_position.distance_to(source) <= radius:
		_target_x = source.x
		_enter(State.INVESTIGATE, 6.0)

func _enter(next: State, duration: float) -> void:
	if next == State.CHASE and is_screamer and not _has_screamed:
		_has_screamed = true
		get_tree().call_group("zombies", "hear_noise", global_position, scream_radius)
		var tween := create_tween()
		tween.tween_property(sprite, "scale", sprite.scale * 1.08, 0.12)
		tween.tween_property(sprite, "scale", sprite.scale, 0.2)
	state = next
	_state_timer = duration

func _apply_facing() -> void:
	sprite.flip_h = facing < 0

func take_damage(amount: int, from_position: Vector2) -> void:
	if state == State.DEAD:
		return
	health -= amount
	var push := 1.0 if global_position.x >= from_position.x else -1.0
	velocity.x = push * 160.0
	facing = -int(push)
	_apply_facing()
	_target_x = from_position.x
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3), 0.04)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.18)
	if health <= 0:
		_die(push)
	else:
		_enter(State.HURT, 0.25)

func _die(push: float) -> void:
	state = State.DEAD
	collision_layer = 0
	died.emit(self)
	var tween := create_tween()
	tween.tween_property(sprite, "rotation", 1.45 * push, 0.4).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sprite, "position:y", 10.0, 0.4)
	tween.tween_interval(2.5)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
