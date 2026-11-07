extends Node
## Обновляется самым последним в кадре (process_priority = 1000): к этому моменту
## все враги, герой и камера уже сдвинулись, поэтому 3D-отражения, предметы и маяки
## встают ровно туда же, где нарисован пол, — без дрожания друг относительно друга.

var main: Node


func _process(delta: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	main._sync_mirrors()
	main._update_beacons(delta)
