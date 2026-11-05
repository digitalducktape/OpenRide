class_name PullBests
extends RefCounted
## The rider's best distance per difficulty, for the flag on the track (#79). Kept in
## `user://the_pull_bests.cfg`, one section per rider (`GameOptions.rider()`, "guest" without
## one), like GameOptions. Not in OpenRide's backup: it is a convenience, and Kotlin keeps the
## real bests (scores) per plan.

const DEFAULT_PATH := "user://the_pull_bests.cfg"

static var path := DEFAULT_PATH


static func get_best(difficulty: String, rider_id := GameOptions.rider()) -> float:
	var config := _load()
	return float(config.get_value(rider_id, difficulty, 0.0))


## Stores `metres` if it beats the stored best. Returns whether it did.
static func offer(difficulty: String, metres: float, rider_id := GameOptions.rider()) -> bool:
	var config := _load()
	if metres <= float(config.get_value(rider_id, difficulty, 0.0)):
		return false
	config.set_value(rider_id, difficulty, snappedf(metres, 0.01))
	config.save(path)
	return true


static func forget_rider(rider_id: String) -> void:
	var config := _load()
	if config.has_section(rider_id):
		config.erase_section(rider_id)
		config.save(path)


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(path)
	return config
