class_name RoomData
extends RefCounted
## Данные комнаты. Комната = данные, не объект в сцене.
## home — домашние координаты (не меняются при сдвигах куба),
## ss   — ключ безопасности (хвост номера).

var home: Vector3i = Vector3i.ZERO
var ss: int = 0


## Номер комнаты в виде "XX YY ZZ SS".
func label() -> String:
	return "%02d %02d %02d %02d" % [home.x, home.y, home.z, ss]


## Простой ли хвост (безопасна от ловушек).
func is_safe_tail() -> bool:
	return CubeWorld.is_prime(ss)
