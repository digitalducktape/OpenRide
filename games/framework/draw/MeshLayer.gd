class_name MeshLayer
extends Node2D
## A Node2D that draws one MeshBatch2D batch: `batch` when it has one (built once and kept), else
## what `paint` (a Callable taking a fresh MeshBatch2D) adds each time it redraws. Balloon Pump's
## and Power Grid's stages are made of these.

var paint: Callable
var batch: MeshBatch2D


func _draw() -> void:
	if batch:
		batch.draw_on(self)
	elif paint.is_valid():
		var m := MeshBatch2D.new()
		paint.call(m)
		m.flush(self)
