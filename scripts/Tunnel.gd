extends Node3D
class_name Tunnel
## Лаз между двумя комнатами: квадратная труба 1.3 м (ползти в приседе),
## для вертикальных связей — шахта с перекладинами (лезть).
## Локальный +Z направлен вдоль лаза, от грани комнаты A к комнате B.

const S := 1.3  ## сторона внутреннего сечения

var tunnel_type := "crawl"  ## "crawl" (горизонтальный) или "climb" (вертикальный)
var length := Room.TUNNEL_LEN

static var mat_wall: StandardMaterial3D = null
static var mat_rib: StandardMaterial3D = null
static var mat_strip: StandardMaterial3D = null


func _init() -> void:
	if mat_wall == null:
		mat_wall = StandardMaterial3D.new()
		mat_wall.albedo_color = Color(0.28, 0.29, 0.32)
		mat_wall.metallic = 0.6
		mat_wall.roughness = 0.55
		mat_wall.cull_mode = BaseMaterial3D.CULL_DISABLED

		mat_rib = StandardMaterial3D.new()
		mat_rib.albedo_color = Color(0.16, 0.17, 0.19)
		mat_rib.metallic = 0.7
		mat_rib.roughness = 0.45

		mat_strip = StandardMaterial3D.new()
		mat_strip.albedo_color = Color(0.8, 0.85, 0.9)
		mat_strip.emission_enabled = true
		mat_strip.emission = Color(0.75, 0.85, 1.0)
		mat_strip.emission_energy_multiplier = 0.5


func setup(dir: Vector3i, len: float) -> void:
	length = len
	tunnel_type = "climb" if dir.y != 0 else "crawl"

	var zax := Vector3(dir)
	var yax := Vector3.UP if dir.y == 0 else Vector3(0, 0, 1)
	var xax := yax.cross(zax).normalized()
	transform = Transform3D(Basis(xax, yax, zax), transform.origin)

	# --- стены лаза (вид + коллизии) ---
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	var t := length + 0.4
	var cz := length * 0.5
	var walls: Array = [
		[Vector3(0.2, S + 0.4, t), Vector3(-(S + 0.2) * 0.5, 0, cz)],
		[Vector3(0.2, S + 0.4, t), Vector3((S + 0.2) * 0.5, 0, cz)],
		[Vector3(S + 0.4, 0.2, t), Vector3(0, -(S + 0.2) * 0.5, cz)],
		[Vector3(S + 0.4, 0.2, t), Vector3(0, (S + 0.2) * 0.5, cz)],
	]
	for w in walls:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = w[0]
		m.mesh = bm
		m.material_override = mat_wall
		m.position = w[1]
		add_child(m)
		var shape := BoxShape3D.new()
		shape.size = w[0]
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = w[1]
		body.add_child(col)

	# --- рёбра жёсткости ---
	var z := 0.4
	while z < length:
		for r in [
			Vector3(0, (S - 0.06) * 0.5, z), Vector3(0, -(S - 0.06) * 0.5, z),
			Vector3((S - 0.06) * 0.5, 0, z), Vector3(-(S - 0.06) * 0.5, 0, z)
		]:
			var rib := MeshInstance3D.new()
			var rb := BoxMesh.new()
			if abs(r.y) > abs(r.x):
				rb.size = Vector3(S, 0.07, 0.09)
			else:
				rb.size = Vector3(0.07, S, 0.09)
			rib.mesh = rb
			rib.material_override = mat_rib
			rib.position = r
			add_child(rib)
		z += 0.6

	# --- тусклые световые полосы по верхним углам ---
	for sx in [-1, 1]:
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.05, 0.05, length)
		strip.mesh = sb
		strip.material_override = mat_strip
		strip.position = Vector3(sx * (S * 0.5 - 0.08), S * 0.5 - 0.08, cz)
		add_child(strip)

	# --- перекладины в вертикальной шахте (у стены -Z комнат) ---
	if tunnel_type == "climb":
		var rz := 0.25
		while rz < length:
			var rung := MeshInstance3D.new()
			var rb2 := BoxMesh.new()
			rb2.size = Vector3(0.5, 0.08, 0.06)
			rung.mesh = rb2
			rung.material_override = mat_rib
			rung.position = Vector3(0, -(S * 0.5 - 0.12), rz)
			add_child(rung)
			rz += 0.45

	# --- зона (ползти / лезть) ---
	var zone := Area3D.new()
	zone.name = "Zone"
	var zs := BoxShape3D.new()
	var ext := 1.0
	zs.size = Vector3(S - 0.1, S - 0.1, length + ext)
	var zc := CollisionShape3D.new()
	zc.shape = zs
	zone.add_child(zc)
	zone.position = Vector3(0, 0, length * 0.5)
	zone.set_meta("zone_type", tunnel_type)
	zone.body_entered.connect(_on_zone_entered)
	zone.body_exited.connect(_on_zone_exited)
	add_child(zone)


func _on_zone_entered(body: Node3D) -> void:
	if body.has_method("set_zone"):
		body.set_zone(tunnel_type, true, Vector3.ZERO)


func _on_zone_exited(body: Node3D) -> void:
	if body.has_method("set_zone"):
		body.set_zone(tunnel_type, false, Vector3.ZERO)
