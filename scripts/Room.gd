extends Node3D
class_name Room
## Комната куба (8 м). Геометрия строится процедурно в setup():
##  - светящиеся панели + стальной каркас (рамка, крест, диагонали, ромбы);
##  - на 4 боковых гранях люк внизу стены (лаз в тоннель), на полу/потолке —
##    люк в вертикальную шахту;
##  - люк = квадратная рамка + дверь-"ирис" в виде креста из 4 полос-пластин,
##    которые разъезжаются по диагоналям в карманы стены;
##  - у стены -Z закреплена лестница к потолочному люку.
## Комната = данные; позиция узла задаётся извне (Main).

const HALF := 4.0            ## половина ребра комнаты (внутри), м
const OPEN := 1.5            ## сторона квадратного проёма люка
const TUNNEL_LEN := 3.0      ## длина лаза между комнатами
const STEP := 2.0 * HALF + TUNNEL_LEN   ## расстояние между центрами соседних комнат
const HATCH_Y := -HALF + 0.35 + OPEN * 2.5 ## высота центра люка боковой грани
const WALL_OFF := -HALF + 4.0             ## смещение вертикальных люков от центра (к стене -Z)
const BEAM_W := 0.12
const BEAM_D := 0.10
const FRAME_W := 0.12        ## ширина рамки люка
const F := OPEN * 0.5 + FRAME_W  ## половина внешней стороны рамки люка

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var coords: Vector3i = Vector3i.ZERO
var data: RoomData = null
## Vector3i -> {plates: Array, collider: CollisionShape3D, open: bool, sealed: bool, label: String}
var hatches: Dictionary = {}

var _shell: StaticBody3D

static var mat_panel: StandardMaterial3D = null
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

		mat_frame = StandardMaterial3D.new()
		mat_frame.albedo_color = Color(0.15, 0.16, 0.18)
		mat_frame.metallic = 0.7
		mat_frame.roughness = 0.45

		mat_door = StandardMaterial3D.new()
		mat_door.albedo_color = Color(0.34, 0.36, 0.40)
		mat_door.metallic = 0.6
		mat_door.roughness = 0.5

		mat_dark = StandardMaterial3D.new()
		mat_dark.albedo_color = Color(0.22, 0.23, 0.25)
		mat_dark.metallic = 0.5
		mat_dark.roughness = 0.6


## Локальный Y-центр проёма люка на грани d.
static func hatch_cy(d: Vector3i) -> float:
	if d.y == 0:
		return HATCH_Y
	return WALL_OFF if d.y > 0 else -WALL_OFF


## Мировое смещение центра проёма люка от центра комнаты.
static func face_center_offset(d: Vector3i) -> Vector3:
	if d.y == 0:
		return Vector3(d) * HALF + Vector3(0, HATCH_Y, 0)
	return Vector3(d) * HALF + Vector3(0, 0, WALL_OFF)


func setup(p_coords: Vector3i, p_data: RoomData) -> void:
	coords = p_coords
	data = p_data
	_shell = StaticBody3D.new()
	_shell.name = "Shell"
	add_child(_shell)
	for d in DIRS:
		var nb := coords + d
		var sealed := not CubeWorld.in_bounds(nb)
		var lbl := "" if sealed else CubeWorld.room_at(nb).label()
		_build_face(d, lbl, sealed)
	_build_wall_ladder()


## Коллайдеры стены вокруг проёма (рамка-картина), в локальных координатах грани.
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


## Базис грани: локальный +Z смотрит ВНУТРЬ комнаты, локальный +Y для
## пола/потолка совпадает с мировым +Z (чтобы люк попал к стене -Z).
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


func _build_face(d: Vector3i, lbl: String, sealed: bool) -> void:
	var cy := hatch_cy(d)
	var horizontal := d.y == 0
	var face := Node3D.new()
	face.name = "Face_%d_%d_%d" % [d.x, d.y, d.z]
	face.transform = Transform3D(_face_basis(d), Vector3(d) * HALF)
	add_child(face)

	# --- светящиеся панели вокруг проёма ---
	var o := OPEN * 0.5
	var top_h := HALF - (cy + o)
	var bot_h := (cy - o) + HALF
	_quad(face, Vector2(0, (HALF + cy + o) * 0.5), Vector2(2 * HALF, top_h))
	_quad(face, Vector2(0, (-HALF + cy - o) * 0.5), Vector2(2 * HALF, bot_h))
	_quad(face, Vector2((-HALF - o) * 0.5, cy), Vector2(HALF - o, OPEN))
	_quad(face, Vector2((HALF + o) * 0.5, cy), Vector2(HALF - o, OPEN))

	# --- внешняя рамка грани ---
	var bd := BEAM_D * 1.3
	_box(face, Vector3(2 * HALF, BEAM_W, bd), Vector3(0, HALF - BEAM_W * 0.5, bd * 0.5), mat_frame)
	_box(face, Vector3(2 * HALF, BEAM_W, bd), Vector3(0, -HALF + BEAM_W * 0.5, bd * 0.5), mat_frame)
	_box(face, Vector3(BEAM_W, 2 * HALF, bd), Vector3(-HALF + BEAM_W * 0.5, 0, bd * 0.5), mat_frame)
	_box(face, Vector3(BEAM_W, 2 * HALF, bd), Vector3(HALF - BEAM_W * 0.5, 0, bd * 0.5), mat_frame)

	# --- каркас: крест + диагонали + ромбы ---
	if horizontal:
		_box(face, Vector3(2 * HALF, BEAM_W, BEAM_D), Vector3(0, 0, BEAM_D * 0.5), mat_frame)
		var vl := HALF - (cy + F)
		_box(face, Vector3(BEAM_W, vl, BEAM_D), Vector3(0, cy + F + vl * 0.5, BEAM_D * 0.5), mat_frame)
		var diag_len := HALF * sqrt(2.0)
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				var mid := Vector2(sx * HALF * 0.5, sy * HALF * 0.5)
				var ang := rad_to_deg(atan2(float(sy), float(sx)))
				_box(face, Vector3(diag_len, BEAM_W * 0.8, BEAM_D * 0.8), Vector3(mid.x, mid.y, BEAM_D * 0.4), mat_frame, ang)
				_box(face, Vector3(0.5, 0.5, 0.1), Vector3(mid.x, mid.y, 0.05), mat_frame, 45.0)
		_box(face, Vector3(1.0, 1.0, 0.1), Vector3(0, 0, 0.05), mat_frame, 45.0)
		_box(face, Vector3(0.55, 0.55, 0.14), Vector3(0, 0, 0.07), mat_frame, 45.0)
	else:
		var seg := HALF - F
		var cm := F + seg * 0.5
		_box(face, Vector3(seg, BEAM_W, BEAM_D), Vector3(cm, cy, BEAM_D * 0.5), mat_frame)
		_box(face, Vector3(seg, BEAM_W, BEAM_D), Vector3(-cm, cy, BEAM_D * 0.5), mat_frame)
		var vt := HALF - (cy + F)
		var vb := (cy - F) + HALF
		_box(face, Vector3(BEAM_W, vt, BEAM_D), Vector3(0, cy + F + vt * 0.5, BEAM_D * 0.5), mat_frame)
		_box(face, Vector3(BEAM_W, vb, BEAM_D), Vector3(0, -HALF + vb * 0.5, BEAM_D * 0.5), mat_frame)
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				var inner := Vector2(sx * F, cy + sy * F)
				var outer := Vector2(sx * HALF, cy + sy * HALF)
				var m1 := (inner + outer) * 0.5
				var ang1 := rad_to_deg(atan2(float(sy), float(sx)))
				var len1 := (outer - inner).length()
				_box(face, Vector3(len1, BEAM_W * 0.8, BEAM_D * 0.8), Vector3(m1.x, m1.y, BEAM_D * 0.4), mat_frame, ang1)
				var c2 := Vector2(sx * HALF, cy + sy * F)
				var c3 := Vector2(sx * F, cy + sy * HALF)
				var m2 := (c2 + c3) * 0.5
				var ang2 := rad_to_deg(atan2(c3.y - c2.y, c3.x - c2.x))
				_box(face, Vector3(len1, BEAM_W * 0.8, BEAM_D * 0.8), Vector3(m2.x, m2.y, BEAM_D * 0.4), mat_frame, ang2)
				_box(face, Vector3(0.4, 0.4, 0.09), Vector3(m1.x, m1.y, 0.045), mat_frame, 45.0)

	if sealed:
		_box(face, Vector3(2 * F, 2 * F, 0.12), Vector3(0, cy, 0.06), mat_door)
		_box(face, Vector3(0.7, 0.7, 0.08), Vector3(0, cy, 0.13), mat_door, 45.0)
		_shell_face(d, cy)
		hatches[d] = {"plates": [], "collider": null, "open": false, "sealed": true, "label": ""}
		return

	# --- рамка люка ---
	_box(face, Vector3(2 * F, FRAME_W, 0.16), Vector3(0, cy + F - FRAME_W * 0.5, 0.08), mat_frame)
	_box(face, Vector3(2 * F, FRAME_W, 0.16), Vector3(0, cy - F + FRAME_W * 0.5, 0.08), mat_frame)
	_box(face, Vector3(FRAME_W, 2 * F, 0.16), Vector3(-F + FRAME_W * 0.5, cy, 0.08), mat_frame)
	_box(face, Vector3(FRAME_W, 2 * F, 0.16), Vector3(F - FRAME_W * 0.5, cy, 0.08), mat_frame)

	# --- дверь-"ирис": 4 пластины с половинами креста, разъезжаются по диагоналям ---
	var iris := Node3D.new()
	iris.name = "Iris"
	iris.position = Vector3(0, cy, -0.10)
	face.add_child(iris)
	var plates: Array = []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var plate := Node3D.new()
			var closed_pos := Vector3(sx * OPEN * 0.25, sy * OPEN * 0.25, 0)
			plate.position = closed_pos
			iris.add_child(plate)
			_box(plate, Vector3(OPEN * 0.5, OPEN * 0.5, 0.06), Vector3.ZERO, mat_door)
			# половины креста по внутренним кромкам пластины
			_box(plate, Vector3(0.09, OPEN * 0.5, 0.06), Vector3(-sx * OPEN * 0.25 + sx * 0.045, 0, 0), mat_frame)
			_box(plate, Vector3(OPEN * 0.5, 0.09, 0.06), Vector3(0, -sy * OPEN * 0.25 + sy * 0.045, 0), mat_frame)
			var open_pos := closed_pos + Vector3(sx, sy, 0) * (OPEN * 0.75)
			plates.append({"node": plate, "closed": closed_pos, "open": open_pos})

	# --- коллайдер закрытой двери ---
	var door_body := StaticBody3D.new()
	door_body.name = "DoorCollider"
	face.add_child(door_body)
	var dshape := BoxShape3D.new()
	dshape.size = Vector3(OPEN, OPEN, 0.18)
	var dcol := CollisionShape3D.new()
	dcol.shape = dshape
	dcol.position = Vector3(0, cy, -0.09)
	door_body.add_child(dcol)

	# --- табличка с номером соседней комнаты ---
	var plate_lbl := Label3D.new()
	plate_lbl.text = lbl
	plate_lbl.pixel_size = 0.004
	plate_lbl.modulate = Color(0.10, 0.10, 0.11)
	plate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate_lbl.position = Vector3(0, cy + F + 0.3, 0.14)
	face.add_child(plate_lbl)

	_shell_face(d, cy)
	hatches[d] = {"plates": plates, "collider": dcol, "open": false, "sealed": false, "label": lbl}


## Лестница у стены -Z: от пола до потолочного люка + зона лазания.
## Колонна лазания центрирована по оси потолочного люка (z = WALL_OFF),
## начинается выше бокового люка, чтобы не мешать ему.
func _build_wall_ladder() -> void:
	var y := -2.0
	while y < HALF - 0.1:
		_box(self, Vector3(0.55, 0.06, 0.12), Vector3(0, y, -HALF + 0.45), mat_frame)
		y += 0.45
	var zone := Area3D.new()
	zone.name = "LadderZone"
	var zs := BoxShape3D.new()
	zs.size = Vector3(1.0, 6.0, 1.0)
	var zc := CollisionShape3D.new()
	zc.shape = zs
	zone.add_child(zc)
	zone.position = Vector3(0, 0.8, -HALF + 0.8)
	zone.set_meta("zone_type", "ladder")
	zone.body_entered.connect(_on_zone_entered)
	zone.body_exited.connect(_on_zone_exited)
	add_child(zone)


func _on_zone_entered(body: Node3D) -> void:
	if body.has_method("set_zone"):
		body.set_zone("ladder", true, Vector3(0, 0, 1))


func _on_zone_exited(body: Node3D) -> void:
	if body.has_method("set_zone"):
		body.set_zone("ladder", false, Vector3(0, 0, 1))


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


## Открыть/закрыть люк: полосы-пластины разъезжаются в карманы стены.
func set_open(d: Vector3i, open: bool) -> void:
	if not hatches.has(d):
		return
	var h: Dictionary = hatches[d]
	if h.sealed or bool(h.open) == open:
		return
	h.open = open
	if h.collider != null:
		h.collider.set_deferred("disabled", open)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_parallel(true)
	for p in h.plates:
		var target: Vector3 = p.open if open else p.closed
		tw.tween_property(p.node, "position", target, 0.55)
