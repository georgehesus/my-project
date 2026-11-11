class_name Room
extends Node3D

# ============================================================
#  Комната куба (8 м).
#
#  Люк стоит В СЕРЕДИНЕ тоннеля: по одной двери с каждой стороны,
#  обе открываются одновременно через общее состояние (shared_hatches).
#  Координаты комнаты пишутся белым на полу тоннеля.
#  Визуал, лестницы и X-узор — из нового Room.gd.
# ============================================================

const HALF := 4.0
const OPEN := 1.5
const TUNNEL_LEN := 3.0
const STEP := 2.0 * HALF + TUNNEL_LEN
const HATCH_Y := -HALF + 0.35 + OPEN * 2.5
const WALL_OFF := 0.0

const BEAM_W := 0.12
const BEAM_D := 0.10
const FRAME_W := 0.12
const F := OPEN * 0.5 + FRAME_W

const LINE_W := 0.34
const HLINE_W := 0.22
const RUNG_STEP := 0.40

# Зазор между двумя дверями в центре тоннеля.
# Если двери цепляют друг друга — увеличь до 0.32.
# Если хочешь ближе — уменьши до 0.16.
const DOOR_GAP := 0.24

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

signal player_near_hatch(dir, near)

var coords: Vector3i = Vector3i.ZERO
var data: RoomData = null
var hatches: Dictionary = {}
var _shell: StaticBody3D

# Общее состояние люков: один ключ на ребро между двумя комнатами.
# Каждая дверь регистрирует сюда свой коллайдер и пластины.
static var shared_hatches: Dictionary = {}

static var mat_panel: StandardMaterial3D = null
static var mat_edge: StandardMaterial3D = null
static var mat_line: StandardMaterial3D = null
static var mat_rib: StandardMaterial3D = null
static var mat_frame: StandardMaterial3D = null
static var mat_door: StandardMaterial3D = null
static var mat_dark: StandardMaterial3D = null


func _init() -> void:
	if mat_panel == null:
		mat_panel = StandardMaterial3D.new()
		mat_panel.albedo_color = Color(0.92, 0.94, 0.97)
		mat_panel.roughness = 0.6
		mat_panel.emission_enabled = true
		mat_panel.emission = Color(1.0, 1.0, 1.0)
		mat_panel.emission_energy_multiplier = 1.2
		mat_panel.cull_mode = BaseMaterial3D.CULL_DISABLED

		mat_edge = StandardMaterial3D.new()
		mat_edge.albedo_color = Color(0.045, 0.045, 0.05)
		mat_edge.metallic = 0.35
		mat_edge.roughness = 0.55

		mat_line = StandardMaterial3D.new()
		mat_line.albedo_color = Color(0.10, 0.11, 0.12)
		mat_line.metallic = 0.55
		mat_line.roughness = 0.5

		mat_rib = StandardMaterial3D.new()
		mat_rib.albedo_color = Color(0.66, 0.69, 0.74)
		mat_rib.metallic = 0.15
		mat_rib.roughness = 0.6
		mat_rib.emission_enabled = true
		mat_rib.emission = Color(1.0, 1.0, 1.0)
		mat_rib.emission_energy_multiplier = 0.35

		mat_frame = StandardMaterial3D.new()
		mat_frame.albedo_color = Color(0.72, 0.75, 0.79)
		mat_frame.metallic = 0.55
		mat_frame.roughness = 0.45
		mat_frame.emission_enabled = true
		mat_frame.emission = Color(1.0, 1.0, 1.0)
		mat_frame.emission_energy_multiplier = 0.25

		mat_door = StandardMaterial3D.new()
		mat_door.albedo_color = Color(0.13, 0.14, 0.16)
		mat_door.metallic = 0.6
		mat_door.roughness = 0.5

		mat_dark = StandardMaterial3D.new()
		mat_dark.albedo_color = Color(0.22, 0.23, 0.25)
		mat_dark.metallic = 0.5
		mat_dark.roughness = 0.6


func _exit_tree() -> void:
	# Убираем свои коллайдеры и пластины из общих люков.
	for d in hatches.keys():
		var h: Dictionary = hatches[d]
		var key: String = h.get("shared_key", "")
		if key == "" or not shared_hatches.has(key):
			continue

		var sh: Dictionary = shared_hatches[key]

		var col = h.get("collider")
		if col != null and is_instance_valid(col):
			sh.colliders.erase(col)

		for p in h.get("plates", []):
			sh.plates.erase(p)

		if sh.colliders.is_empty() and sh.plates.is_empty():
			shared_hatches.erase(key)


# ==================== статические хелперы ====================

static func hatch_cy(d: Vector3i) -> float:
	if d.y == 0:
		return HATCH_Y
	return WALL_OFF if d.y > 0 else -WALL_OFF


static func face_center_offset(d: Vector3i) -> Vector3:
	if d.y == 0:
		return Vector3(d) * HALF + Vector3(0, HATCH_Y, 0)
	return Vector3(d) * HALF + Vector3(0, 0, WALL_OFF)


static func _edge_key(c: Vector3i, d: Vector3i) -> String:
	var a := c
	var b := c + d
	if b.x < a.x or b.y < a.y or b.z < a.z:
		var t := a
		a = b
		b = t
	return "%d,%d,%d>%d,%d,%d" % [a.x, a.y, a.z, b.x, b.y, b.z]


static func _seg_intersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> Vector2:
	var r := p2 - p1
	var s := q2 - q1
	var den := r.cross(s)
	if absf(den) < 1e-6:
		return (p1 + p2) * 0.5
	var t := (q1 - p1).cross(s) / den
	return p1 + r * t


# ==================== общие люки ====================

func _get_shared(key: String) -> Dictionary:
	if not shared_hatches.has(key):
		shared_hatches[key] = {
			"open": false,
			"colliders": [],
			"plates": [],
		}
	return shared_hatches[key]


func _register_shared(d: Vector3i, collider: CollisionShape3D, plates: Array) -> String:
	var key := _edge_key(coords, d)
	var sh := _get_shared(key)

	if collider != null:
		sh.colliders.append(collider)

	for p in plates:
		sh.plates.append(p)

	return key


# ==================== setup ====================

func label() -> String:
	if data != null and data.has_method("label"):
		return data.label()
	return ""


func setup(p_coords: Vector3i, p_data: RoomData) -> void:
	coords = p_coords
	data = p_data

	_shell = StaticBody3D.new()
	_shell.name = "Shell"
	add_child(_shell)

	for d in DIRS:
		var nb := coords + d
		var sealed := not CubeWorld.in_bounds(nb)

		var lbl := ""
		if not sealed:
			var r: Variant = CubeWorld.room_at(nb)
			if r != null and r.has_method("label"):
				lbl = r.label()

		_build_face(d, lbl, sealed)

	_build_center_climb()


# Публичный алиас на случай, если Main вызывает старый вариант.
func build_face(d: Vector3i, lbl: String, sealed: bool) -> void:
	_build_face(d, lbl, sealed)


# ==================== построение грани ====================

func _build_face(d: Vector3i, lbl: String, sealed: bool) -> void:
	var cy := hatch_cy(d)
	var is_wall := d.y == 0

	var face := Node3D.new()
	face.name = "Face_%d_%d_%d" % [d.x, d.y, d.z]
	face.transform = Transform3D(_face_basis(d), Vector3(d) * HALF)
	add_child(face)

	if sealed:
		_quad(face, Vector2(0, 0), Vector2(2 * HALF, 2 * HALF))

		var shape := BoxShape3D.new()
		shape.size = Vector3(2 * HALF, 2 * HALF, 0.2)

		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = Transform3D(_face_basis(d), Vector3(d) * HALF)
		_shell.add_child(col)

		hatches[d] = {
			"plates": [],
			"collider": null,
			"open": false,
			"sealed": true,
			"label": lbl,
			"has_hatch": false,
			"closing": false,
		}
		return

	# --- светящиеся панели вокруг проёма ---
	var o := OPEN * 0.5
	var top_h := HALF - (cy + o)
	var bot_h := (cy - o) + HALF

	_quad(face, Vector2(0, (HALF + cy + o) * 0.5), Vector2(2 * HALF, top_h))
	_quad(face, Vector2(0, (-HALF + cy - o) * 0.5), Vector2(2 * HALF, bot_h))
	_quad(face, Vector2((-HALF - o) * 0.5, cy), Vector2(HALF - o, OPEN))
	_quad(face, Vector2((HALF + o) * 0.5, cy), Vector2(HALF - o, OPEN))

	# --- чёрная внешняя рамка грани ---
	var bd := BEAM_D * 1.3
	_box(face, Vector3(2 * HALF, BEAM_W, bd), Vector3(0, HALF - BEAM_W * 0.5, bd * 0.5), mat_edge)
	_box(face, Vector3(2 * HALF, BEAM_W, bd), Vector3(0, -HALF + BEAM_W * 0.5, bd * 0.5), mat_edge)
	_box(face, Vector3(BEAM_W, 2 * HALF, bd), Vector3(-HALF + BEAM_W * 0.5, 0, bd * 0.5), mat_edge)
	_box(face, Vector3(BEAM_W, 2 * HALF, bd), Vector3(HALF - BEAM_W * 0.5, 0, bd * 0.5), mat_edge)

	# --- тёмные линии креста ---
	var seg := HALF - F
	var cm := F + seg * 0.5

	_box(face, Vector3(seg, HLINE_W, BEAM_D), Vector3(cm, cy, BEAM_D * 0.5), mat_line)
	_box(face, Vector3(seg, HLINE_W, BEAM_D), Vector3(-cm, cy, BEAM_D * 0.5), mat_line)

	var vt := HALF - (cy + F)
	var vb := (cy - F) + HALF

	_box(face, Vector3(LINE_W, vt, BEAM_D), Vector3(0, cy + F + vt * 0.5, BEAM_D * 0.5), mat_line)
	_box(face, Vector3(LINE_W, vb, BEAM_D), Vector3(0, -HALF + vb * 0.5, BEAM_D * 0.5), mat_line)

	# --- X-узор ---
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var a1 := Vector2(sx * F, cy + sy * F)
			var a2 := Vector2(sx * HALF, sy * HALF)
			var b1 := Vector2(sx * HALF, cy)
			var b2 := Vector2(0.0, sy * HALF)

			_beam(face, a1, a2, BEAM_W * 0.7, BEAM_D * 0.8, mat_rib)
			_beam(face, b1, b2, BEAM_W * 0.7, BEAM_D * 0.8, mat_rib)

			var c := _seg_intersect(a1, a2, b1, b2)
			_box(face, Vector3(0.45, 0.45, 0.09), Vector3(c.x, c.y, 0.045), mat_rib, 45.0)

	# --- лестницы на боковых стенах ---
	if is_wall:
		var y := -HALF + 0.3
		while y < HALF - 0.15:
			if absf(y - cy) > F + 0.15:
				_box(face, Vector3(LINE_W - 0.06, 0.06, 0.08), Vector3(0, y, BEAM_D), mat_edge)
			y += RUNG_STEP

		var zone := Area3D.new()
		zone.name = "LadderZone_%d_%d_%d" % [d.x, d.y, d.z]

		var zs := BoxShape3D.new()
		zs.size = Vector3(1.6, 2 * HALF - 0.2, 1.2)

		var zc := CollisionShape3D.new()
		zc.shape = zs
		zone.add_child(zc)

		zone.position = Vector3(0, 0, 0.6)
		zone.set_meta("zone_type", "ladder")

		var n := -Vector3(d)
		zone.body_entered.connect(_on_ladder_entered.bind(n))
		zone.body_exited.connect(_on_ladder_exited.bind(n))
		face.add_child(zone)

	# --- коллайдеры стены вокруг проёма ---
	_shell_face(d, cy)

	# --- половина тоннеля с белыми координатами на полу ---
	_build_tunnel_half(face, cy, lbl, is_wall)

	# --- люк в середине тоннеля ---
	_build_hatch_in_tunnel(d, cy, lbl)


# ==================== коллайдеры стены ====================

func _shell_face(d: Vector3i, cy: float) -> void:
	var face_basis := _face_basis(d)
	var o := OPEN * 0.5

	var parts: Array = [
		[Vector3(2 * HALF, HALF - (cy + o), 0.2), Vector3(0, (HALF + cy + o) * 0.5, -0.1)],
		[Vector3(2 * HALF, (cy - o) + HALF, 0.2), Vector3(0, (-HALF + cy - o) * 0.5, -0.1)],
		[Vector3(HALF - o, OPEN, 0.2), Vector3((-HALF - o) * 0.5, cy, -0.1)],
		[Vector3(HALF - o, OPEN, 0.2), Vector3((HALF + o) * 0.5, cy, -0.1)],
	]

	for p in parts:
		var shape := BoxShape3D.new()
		shape.size = p[0]

		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = Transform3D(face_basis, face_basis * p[1] + Vector3(d) * HALF)
		_shell.add_child(col)


func _face_basis(d: Vector3i) -> Basis:
	var zax := -Vector3(d)
	var xax: Vector3
	var yax: Vector3

	if d.y != 0:
		yax = Vector3(0, 0, 1) if d.y > 0 else Vector3(0, 0, -1)
		xax = yax.cross(zax).normalized()
	else:
		xax = Vector3.UP.cross(zax).normalized()
		yax = zax.cross(xax).normalized()

	return Basis(xax, yax, zax)


# ==================== половина тоннеля ====================

func _build_tunnel_half(face: Node3D, cy: float, lbl: String, is_wall: bool) -> void:
	var o := OPEN * 0.5

	# Длина половины тоннеля: от стены до дверей (не доходя до них).
	var half_len := TUNNEL_LEN * 0.5 - DOOR_GAP
	if half_len <= 0.2:
		half_len = 0.2

	var zc := -half_len * 0.5
	var side := 0.06

	# --- визуал: пол, потолок, боковые стенки ---
	_box(face, Vector3(OPEN + side * 2.0, 0.08, half_len), Vector3(0, cy - o - 0.05, zc), mat_panel)
	_box(face, Vector3(OPEN + side * 2.0, 0.08, half_len), Vector3(0, cy + o + 0.05, zc), mat_panel)
	_box(face, Vector3(0.08, OPEN, half_len), Vector3(-o - 0.05, cy, zc), mat_dark)
	_box(face, Vector3(0.08, OPEN, half_len), Vector3(o + 0.05, cy, zc), mat_dark)

	# --- коллайдеры тоннеля ---
	var body := StaticBody3D.new()
	body.name = "TunnelHalf"
	face.add_child(body)

	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(OPEN + side * 2.0, 0.1, half_len)
	var floor_col := CollisionShape3D.new()
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0, cy - o - 0.05, zc)
	body.add_child(floor_col)

	var ceil_shape := BoxShape3D.new()
	ceil_shape.size = Vector3(OPEN + side * 2.0, 0.1, half_len)
	var ceil_col := CollisionShape3D.new()
	ceil_col.shape = ceil_shape
	ceil_col.position = Vector3(0, cy + o + 0.05, zc)
	body.add_child(ceil_col)

	var left_shape := BoxShape3D.new()
	left_shape.size = Vector3(0.1, OPEN, half_len)
	var left_col := CollisionShape3D.new()
	left_col.shape = left_shape
	left_col.position = Vector3(-o - 0.05, cy, zc)
	body.add_child(left_col)

	var right_shape := BoxShape3D.new()
	right_shape.size = Vector3(0.1, OPEN, half_len)
	var right_col := CollisionShape3D.new()
	right_col.shape = right_shape
	right_col.position = Vector3(o + 0.05, cy, zc)
	body.add_child(right_col)

	# --- белые координаты на полу тоннеля ---
	# Если текст перевёрнут, замени поворот на Vector3(-90, 0, 180).
	if is_wall and lbl != "":
		var floor_label := Label3D.new()
		floor_label.text = lbl
		floor_label.pixel_size = 0.0045
		floor_label.modulate = Color(1.0, 1.0, 1.0)
		floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		floor_label.rotation_degrees = Vector3(-90, 0, 0)
		floor_label.position = Vector3(0, cy - o + 0.02, zc)
		face.add_child(floor_label)


# ==================== люк в середине тоннеля ====================

func _build_hatch_in_tunnel(d: Vector3i, cy: float, lbl: String) -> void:
	var face_basis := _face_basis(d)
	var tunnel_mid := Vector3(d) * (HALF + TUNNEL_LEN * 0.5)
	var door_off := DOOR_GAP * 0.5

	# Смещаем дверь от центра тоннеля к своей комнате.
	var hatch_origin := tunnel_mid + face_basis * Vector3(0, 0, door_off)

	var hatch_node := Node3D.new()
	hatch_node.name = "Hatch_%d_%d_%d" % [d.x, d.y, d.z]
	hatch_node.transform = Transform3D(face_basis, hatch_origin)
	add_child(hatch_node)

	# --- светлая рамка люка ---
	_box(hatch_node, Vector3(2 * F, FRAME_W, 0.16), Vector3(0, cy + F - FRAME_W * 0.5, 0.08), mat_frame)
	_box(hatch_node, Vector3(2 * F, FRAME_W, 0.16), Vector3(0, cy - F + FRAME_W * 0.5, 0.08), mat_frame)
	_box(hatch_node, Vector3(FRAME_W, 2 * F, 0.16), Vector3(-F + FRAME_W * 0.5, cy, 0.08), mat_frame)
	_box(hatch_node, Vector3(FRAME_W, 2 * F, 0.16), Vector3(F - FRAME_W * 0.5, cy, 0.08), mat_frame)

	# --- ирис с X-узором ---
	var iris := Node3D.new()
	iris.name = "Iris"
	iris.position = Vector3(0, cy, -0.04)
	iris.rotation_degrees = Vector3(0, 0, 45.0)
	hatch_node.add_child(iris)

	var plates: Array = []
	var plate_gap := 0.04
	var plate_size := OPEN * 0.5 - plate_gap

	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var plate := Node3D.new()

			var closed_pos := Vector3(
				sx * (OPEN * 0.25 + plate_gap * 0.5),
				sy * (OPEN * 0.25 + plate_gap * 0.5),
				0
			)

			plate.position = closed_pos
			iris.add_child(plate)

			_box(plate, Vector3(plate_size, plate_size, 0.06), Vector3.ZERO, mat_door)

			var diag_len := plate_size * 0.7
			_box(plate, Vector3(diag_len, 0.08, 0.07), Vector3.ZERO, mat_frame, 45.0)
			_box(plate, Vector3(diag_len, 0.08, 0.07), Vector3.ZERO, mat_frame, -45.0)

			var open_pos := closed_pos + Vector3(sx, sy, 0) * (OPEN * 0.75)
			plates.append({"node": plate, "closed": closed_pos, "open": open_pos})

	# --- коллайдер закрытой двери ---
	var door_body := StaticBody3D.new()
	door_body.name = "DoorCollider"
	hatch_node.add_child(door_body)

	var dshape := BoxShape3D.new()
	dshape.size = Vector3(OPEN, OPEN, 0.18)

	var dcol := CollisionShape3D.new()
	dcol.shape = dshape
	dcol.position = Vector3(0, cy, -0.02)
	door_body.add_child(dcol)

	# --- зона E в центре тоннеля ---
	var interact_zone := Area3D.new()
	interact_zone.name = "InteractZone_%d_%d_%d" % [d.x, d.y, d.z]

	var izs := BoxShape3D.new()
	izs.size = Vector3(OPEN * 1.5, OPEN * 1.5, TUNNEL_LEN * 0.8)

	var izc := CollisionShape3D.new()
	izc.shape = izs
	interact_zone.add_child(izc)

	interact_zone.position = Vector3(0, cy, -door_off)
	interact_zone.set_meta("hatch_dir", d)
	interact_zone.body_entered.connect(_on_player_near_hatch.bind(d, true))
	interact_zone.body_exited.connect(_on_player_near_hatch.bind(d, false))
	hatch_node.add_child(interact_zone)

	# --- зона автозакрытия (уже за обеими дверями) ---
	var close_zone := Area3D.new()
	close_zone.name = "HatchCloseZone_%d_%d_%d" % [d.x, d.y, d.z]

	var czs := BoxShape3D.new()
	czs.size = Vector3(OPEN * 0.8, OPEN * 0.8, 0.35)

	var czc := CollisionShape3D.new()
	czc.shape = czs
	close_zone.add_child(czc)

	close_zone.position = Vector3(0, cy, -0.55)
	close_zone.set_meta("hatch_dir", d)
	close_zone.body_entered.connect(_on_player_passed_hatch.bind(d))
	hatch_node.add_child(close_zone)

	# --- регистрируем дверь в общем люке ---
	var key := _register_shared(d, dcol, plates)

	hatches[d] = {
		"plates": plates,
		"collider": dcol,
		"open": false,
		"sealed": false,
		"label": lbl,
		"has_hatch": true,
		"closing": false,
		"shared_key": key,
	}

	# Если общий люк уже открыт (например, открыли с другой стороны),
	# сразу открываем и эту дверь.
	var sh := _get_shared(key)
	if bool(sh.open):
		dcol.set_deferred("disabled", true)
		for p in plates:
			var node: Node3D = p.get("node")
			if node != null:
				node.position = p.get("open")


# ==================== центральная зона лазания ====================

func _build_center_climb() -> void:
	var zone := Area3D.new()
	zone.name = "CenterClimbZone"

	var zs := BoxShape3D.new()
	zs.size = Vector3(1.5, 2 * HALF - 0.4, 1.5)

	var zc := CollisionShape3D.new()
	zc.shape = zs
	zone.add_child(zc)

	zone.position = Vector3(0, 0, 0)
	zone.set_meta("zone_type", "ladder")

	zone.body_entered.connect(_on_ladder_entered.bind(Vector3.UP))
	zone.body_exited.connect(_on_ladder_exited.bind(Vector3.UP))
	add_child(zone)


# ==================== сигналы зон ====================

func _on_ladder_entered(body: Node3D, n: Vector3) -> void:
	if body.has_method("set_zone"):
		body.set_zone("ladder", true, n)


func _on_ladder_exited(body: Node3D, n: Vector3) -> void:
	if body.has_method("set_zone"):
		body.set_zone("ladder", false, n)


func _on_player_near_hatch(body: Node3D, d: Vector3i, near: bool) -> void:
	if not body.is_in_group("player"):
		return
	player_near_hatch.emit(d, near)


func _on_player_passed_hatch(body: Node3D, d: Vector3i) -> void:
	if not body.is_in_group("player"):
		return

	if not hatches.has(d):
		return

	var h: Dictionary = hatches[d]

	if not h.get("has_hatch", false):
		return
	if h.get("sealed", true):
		return

	var key: String = h.get("shared_key", _edge_key(coords, d))
	var sh := _get_shared(key)

	if not bool(sh.open):
		return
	if bool(h.get("closing", false)):
		return

	h.closing = true

	await get_tree().create_timer(0.5).timeout

	if is_instance_valid(self):
		set_open(d, false)
		h.closing = false


# ==================== поиск и открытие люка ====================

func get_nearest_closed_hatch(player_pos: Vector3) -> Vector3i:
	var nearest := Vector3i.ZERO
	var min_dist := INF

	for d in hatches.keys():
		var h: Dictionary = hatches[d]

		if not h.get("has_hatch", false):
			continue
		if h.get("sealed", true):
			continue

		# Смотрим на общее состояние люка, а не только на локальное.
		var key: String = h.get("shared_key", "")
		if key != "" and shared_hatches.has(key):
			if bool(shared_hatches[key].open):
				continue

		var tunnel_mid := Vector3(d) * (HALF + TUNNEL_LEN * 0.5)
		var dist := player_pos.distance_to(global_transform * tunnel_mid)

		if dist < min_dist:
			min_dist = dist
			nearest = d

	if min_dist < 3.5:
		return nearest

	return Vector3i.ZERO


func set_open(d: Vector3i, open: bool) -> void:
	if not hatches.has(d):
		return

	var h: Dictionary = hatches[d]

	if not h.get("has_hatch", false):
		return
	if h.get("sealed", true):
		return

	var key: String = h.get("shared_key", _edge_key(coords, d))
	var sh := _get_shared(key)

	if bool(sh.open) == open:
		return

	sh.open = open
	h.open = open

	# Отключаем / включаем ВСЕ коллайдеры этого общего люка
	# (и свои, и соседней комнаты).
	var alive_cols: Array = []
	for col in sh.colliders:
		if is_instance_valid(col):
			col.set_deferred("disabled", open)
			alive_cols.append(col)
	sh.colliders = alive_cols

	# Анимируем ВСЕ пластины этого общего люка.
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_parallel(true)

	var alive_plates: Array = []
	for p in sh.plates:
		var node: Node3D = p.get("node")
		if node != null and is_instance_valid(node):
			var target: Vector3 = p.get("open") if open else p.get("closed")
			tw.tween_property(node, "position", target, 0.55)
			alive_plates.append(p)
	sh.plates = alive_plates


# ==================== примитивы ====================

func _quad(parent: Node3D, c: Vector2, s: Vector2) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = s

	m.mesh = pm
	m.material_override = mat_panel
	m.rotation_degrees = Vector3(90, 0, 0)
	m.position = Vector3(c.x, c.y, 0)

	parent.add_child(m)


func _box(parent: Node3D, s: Vector3, p: Vector3, mat: StandardMaterial3D, rot_z_deg := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s

	m.mesh = bm
	m.material_override = mat
	m.position = p
	m.rotation_degrees = Vector3(0, 0, rot_z_deg)

	parent.add_child(m)

	return m


func _beam(parent: Node3D, a: Vector2, b: Vector2, w: float, dd: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var delta := b - a
	var ang := rad_to_deg(atan2(delta.y, delta.x))

	return _box(
		parent,
		Vector3(delta.length(), w, dd),
		Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, dd * 0.5),
		mat,
		ang
	)
