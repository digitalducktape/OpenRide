class_name Stars
extends RefCounted
## Score → 0-3 stars against a game's per-difficulty thresholds (epic #31, "Stars"). Stars let
## different games add up in a circuit. A skipped segment earns none.


## thresholds: [one, two, three], the minimum score for each star. With `per_minute`, they are
## points per minute of gameplay and `played_sec` scales them. Unknown difficulties fall back
## to "standard".
static func for_score(score: float, info: GameInfo, difficulty: String, played_sec := 0.0) -> int:
	var thresholds = info.star_thresholds.get(difficulty, info.star_thresholds.get("standard", []))
	var value := score
	if info.stars_per_minute:
		if played_sec <= 0.0:
			return 0
		value = score / (played_sec / 60.0)
	return count(value, thresholds)


## How many of the three thresholds `value` reaches.
static func count(value: float, thresholds: Array) -> int:
	var stars := 0
	for t in thresholds:
		if value >= float(t):
			stars += 1
	return mini(stars, 3)
