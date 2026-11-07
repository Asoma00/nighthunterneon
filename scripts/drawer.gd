extends Node2D
## Узел, который рисует себя через переданную функцию (для следов клинков и т.п.).

var draw_fn: Callable


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
