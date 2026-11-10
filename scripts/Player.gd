extends CharacterBody3D
class_name Player
## Контроллер от первого лица: ходьба/бег/прыжок, присед и ползание в лазах,
## лазание по шахтам и настенной лестнице, обзор мышью, E — люки.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.0
const CRAWL_SPEED := 1.7
const CLIMB_SPEED := 2.3
const JUMP_VELOCITY := 4.8
const JUMP_CROUCHED := 3.6
const GRAVITY := 9.8
const MOUSE_SENS := 0.0026

var yaw := 0.0
var pitch := 0.0
var main: Main = null
var crouching := false
var crawl_n := 0    ## зон "ползти" (горизонтальные лазы)
var climb_n := 0    ## зон "лезть" (вертикальные шахты)
var ladder_n := 0   ## зона настенной лестницы
var ladder_normal := Vector3.ZERO

@onready var head: Node3D = $Head
@onready var hud: HUD = $HUD
@onready var col_shape: CollisionShape3D = $CollisionShape
@onready var shape: CapsuleShape3D = $CollisionShape.shape


func _ready() -> void:
	main = get_parent() as Main
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Вызывается зонами (Room / Tunnel).
func set_zone(type: String, entered: bool, normal: Vector3) -> void:
	var d := 1 if entered else -1
	match type:
		"crawl":
			crawl_n = maxi(0, crawl_n + d)
		"climb":
			climb_n = maxi(0, climb_n + d)
		"ladder":
			ladder_n = maxi(0, ladder_n + d)
			if entered:
				ladder_normal = normal
			elif ladder_n == 0:
				ladder_normal = Vector3.ZERO


## Настенная лестница активна, только если смотреть на стену.
func ladder_active() -> bool:
	if ladder_n <= 0 or ladder_normal == Vector3.ZERO:
		return false
	var fwd := -global_transform.basis.z
	return fwd.dot(ladder_normal) < -0.5


func climb_engaged() -> bool:
	return climb_n > 0 or ladder_active()


func _set_crouch(on: bool) -> void:
	crouching = on
	shape.height = 1.05 if on else 1.8
	col_shape.position.y = 0.525 if on else 0.9


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.is_action_pressed("interact") and main != null:
			main.try_interact()
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
		rotation.y = yaw
		head.rotation.x = pitch


func _physics_process(delta: float) -> void:
	var want_crouch := Input.is_action_pressed("crouch") or crawl_n > 0
	if want_crouch != crouching:
		_set_crouch(want_crouch)

	var vel := velocity
	var forward := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var right := forward.cross(Vector3.UP)
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir += forward
	if Input.is_action_pressed("move_back"):
		dir -= forward
	if Input.is_action_pressed("move_right"):
		dir += right
	if Input.is_action_pressed("move_left"):
		dir -= right
	var dirn := dir.normalized() if dir.length_squared() > 0.0 else Vector3.ZERO

	if climb_engaged():
		# лазание: W/S вверх-вниз, гравитация выключена
		vel.y = 0.0
		var up := 0.0
		if Input.is_action_pressed("move_forward"):
			up += 1.0
		if Input.is_action_pressed("move_back"):
			up -= 1.0
		vel.y = up * CLIMB_SPEED
		vel.x = dirn.x * CRAWL_SPEED
		vel.z = dirn.z * CRAWL_SPEED
	else:
		if not is_on_floor():
			vel.y -= GRAVITY * delta
		if Input.is_action_just_pressed("jump") and is_on_floor():
			vel.y = JUMP_CROUCHED if crouching else JUMP_VELOCITY
		var speed := CRAWL_SPEED if crouching else (SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED)
		if dirn != Vector3.ZERO:
			vel.x = dirn.x * speed
			vel.z = dirn.z * speed
		else:
			vel.x = move_toward(vel.x, 0.0, speed * 10.0 * delta)
			vel.z = move_toward(vel.z, 0.0, speed * 10.0 * delta)

	velocity = vel
	move_and_slide()

	if main != null and hud != null:
		hud.set_prompt(main.get_prompt())
		hud.set_room("КОМНАТА  " + CubeWorld.room_at(main.current_coords).label())
