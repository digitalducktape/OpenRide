class_name SafeBackdrop
extends Node2D
## The room behind the safe (#41): redrawn only when the place changes.

var place_index := 0


func set_place(index: int) -> void:
	place_index = index
	queue_redraw()


func _draw() -> void:
	SafePlaces.draw_room(self, place_index)
