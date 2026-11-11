extends Node3D
class_name Main
## Главный узел: текущая комната + соединение (лаз + соседняя комната),
## которое грузится только когда люк открыт. Никаких телепортов: игрок
## физически ползёт/лезет через лаз, текущая комната меняется в момент
## пересечения границы. Люки закрываются сами, когда игрок отошёл/спрыгнул.

const START_COORDS := Vector3i(13, 13, 13)

var current_coords: Vector3i = START_COORDS
var current_room: Room = null
## {dir, tunnel, other, other_coords, crossed, cross_timer} или пусто
var conn: Dictionary = {}

var room_scene: PackedScene = preload("res://scenes/Room.tscn")

@onready var player: Player = $Player


func _ready() -> void:
	_load_room(current_coords)
	player.global_position = Vector3(0.0, -Room.HALF + 0.05, 2.0)


func _load_room(coords: Vector3i) -> void:
	current_room = room_scene.instantiate()
	add_child(current_room)
	current_room.setup(coords, CubeWorld.room_at(coords))
	current_room.position = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if player == null or current_room == null:
		return
	#_auto_open()
	if conn.is_empty():
		return

	var dirn := Vector3(conn.dir)
	var s := (player.global_position - current_room.global_position).dot(dirn)

	# пересечение границы: игрок полностью в соседней комнате -> смена текущей
	if s > Room.HALF + Room.TUNNEL_LEN + 0.4:
		_swap()
		dirn = Vector3(conn.dir)
		s = (player.global_position - current_room.global_position).dot(dirn)

	var in_tunnel := s > Room.HALF - 0.3 and s < Room.HALF + Room.TUNNEL_LEN + 0.3

	# авто-открытие у проёма и авто-закрытие когда игрок отошёл
	for door in _conn_doors():
		var is_exit_door: bool = bool(conn.crossed) and door.room == current_room and door.d == conn.dir
		var dist := player.global_position.distance_to(door.center)
		if dist < 1.7 and not is_exit_door:
			door.room.set_open(door.d, true)
		elif dist > 2.4 and not in_tunnel:
			door.room.set_open(door.d, false)

	# после перехода выходной люк закрывается сам (игрок спрыгнул/отошёл)
	if conn.crossed and not in_tunnel:
		conn.cross_timer -= delta
		if conn.cross_timer <= 0.0:
			current_room.set_open(conn.dir, false)

	# выгрузка соединения, когда оба люка закрыты и игрок не в лазе
	var h1: Dictionary = current_room.hatches[conn.dir]
	var h2: Dictionary = conn.other.hatches[-conn.dir]
	if not h1.open and not h2.open and not in_tunnel:
		_free_conn()


## Люки открываются сами, когда игрок подошёл к проёму вплотную.
func _auto_open() -> void:
	for d in Room.DIRS:
		var h: Dictionary = current_room.hatches[d]
		if h.sealed:
			continue
		var c := current_room.global_position + Room.face_center_offset(d)
		if player.global_position.distance_to(c) < 1.6:
			_ensure_conn(d)
			current_room.set_open(d, true)


func _ensure_conn(d: Vector3i) -> void:
	if not conn.is_empty():
		if conn.dir == d:
			return
		_free_conn()
	var tunnel := Tunnel.new()
	add_child(tunnel)
	tunnel.setup(d, Room.TUNNEL_LEN)
	tunnel.global_position = current_room.global_position + Room.face_center_offset(d)
	var other: Room = room_scene.instantiate()
	add_child(other)
	other.setup(current_coords + d, CubeWorld.room_at(current_coords + d))
	other.global_position = current_room.global_position + Vector3(d) * Room.STEP
	conn = {
		"dir": d,
		"tunnel": tunnel,
		"other": other,
		"other_coords": current_coords + d,
		"crossed": false,
		"cross_timer": 0.8,
	}


func _swap() -> void:
	var old_room: Room = current_room
	var old_coords: Vector3i = current_coords
	current_room = conn.other
	current_coords = conn.other_coords
	conn.other = old_room
	conn.other_coords = old_coords
	conn.dir = -conn.dir
	conn.crossed = true
	conn.cross_timer = 0.8


func _conn_doors() -> Array:
	return [
		{
			"room": current_room,
			"d": conn.dir,
			"center": current_room.global_position + Room.face_center_offset(conn.dir),
		},
		{
			"room": conn.other,
			"d": -conn.dir,
			"center": conn.other.global_position + Room.face_center_offset(-conn.dir),
		},
	]


func _free_conn() -> void:
	if conn.is_empty():
		return
	conn.tunnel.queue_free()
	conn.other.queue_free()
	conn = {}


## Люк, на который смотрит игрок.
func get_faced_hatch() -> Dictionary:
	if current_room == null or player == null:
		return {}
	var head: Node3D = player.head
	var cam_pos: Vector3 = head.global_position
	var fwd: Vector3 = -head.global_transform.basis.z
	var best: Dictionary = {}
	var best_dot := 0.6
	for key in current_room.hatches:
		var hatch: Dictionary = current_room.hatches[key]
		var center: Vector3 = current_room.global_position + Room.face_center_offset(key)
		var to: Vector3 = center - cam_pos
		var dist := to.length()
		if dist > 3.2 or dist < 0.001:
			continue
		var dot := (to / dist).dot(fwd)
		if dot > best_dot:
			best_dot = dot
			best = {"dir": key, "hatch": hatch}
	return best


func get_prompt() -> String:
	if player != null and player.climb_engaged():
		return "W / S — лезть  ·  отпусти стену, чтобы слезть"
	var faced := get_faced_hatch()
	if faced.is_empty():
		return ""
	var hatch: Dictionary = faced.hatch
	if hatch.sealed:
		return "Люк запечатан"
	if hatch.open:
		return "Проход открыт  ·  " + str(hatch.label)
	return "[E]  Открыть люк  ·  " + str(hatch.label)


func try_interact() -> void:
	var faced := get_faced_hatch()
	if faced.is_empty():
		return
	var hatch: Dictionary = faced.hatch
	if hatch.sealed:
		return
	if not hatch.open:
		_ensure_conn(faced.dir)
		current_room.set_open(faced.dir, true)
