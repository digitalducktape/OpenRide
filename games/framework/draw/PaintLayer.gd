class_name PaintLayer
extends Node2D
## A child layer drawn by a callable taking the layer itself (`paint.call(self)`), so each layer
## of a code-drawn game is one node and usually one MeshBatch2D batch. From Safe Cracker's dial;
## Keepy Uppy and Ready for Launch draw their rigs, rockets and skies with it.

var paint: Callable


func _draw() -> void:
	if paint.is_valid():
		paint.call(self)
