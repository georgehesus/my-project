extends Node
## CubeWorld — autoload. Хранит таблицу Map[coords] = RoomData и правила мира.
## Сейчас сдвигов ещё нет, поэтому Map = тождественное отображение:
## комната с домашними координатами C стоит в точке C.
## Позже здесь же появятся циклы поворотов (шаг 2).

const CUBE_SIZE := 26

var _cache: Dictionary = {}


func in_bounds(c: Vector3i) -> bool:
	return (
		c.x >= 0 and c.y >= 0 and c.z >= 0
		and c.x < CUBE_SIZE and c.y < CUBE_SIZE and c.z < CUBE_SIZE
	)


## Какая комната сейчас находится в точке c.
## Позже здесь будет обращение к таблице Map, обновляемой сдвигами.
func room_at(c: Vector3i) -> RoomData:
	if _cache.has(c):
		return _cache[c]
	var rd := RoomData.new()
	rd.home = c
	rd.ss = ss_for(c)
	_cache[c] = rd
	return rd


## Детерминированный ключ безопасности SS (00..99) для домашних координат.
func ss_for(c: Vector3i) -> int:
	var h := (c.x * 73856093) ^ (c.y * 19349663) ^ (c.z * 83492791)
	h = (h >> 4) ^ (h * 1103515245)
	h = h & 0x7FFFFFFF
	return h % 100


static func is_prime(n: int) -> bool:
	if n < 2:
		return false
	var i := 2
	while i * i <= n:
		if n % i == 0:
			return false
		i += 1
	return true
