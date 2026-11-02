extends Game
## Keepy Uppy (#77): keep a balloon in the air over a fan your pedalling drives.


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "keepy_uppy"
	i.title = "Keepy Uppy"
	i.how_to = "Pedal to keep the balloon up"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["work"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points a minute (DESIGN.md "Bands and scoring"): steady mid at 1.0× is 1200 (2 stars), always
	# high at 1.0× 1800 (short of 3); 3 stars takes riding high with about 1.3× effort
	# (keepy_logic_test). The weight scales with difficulty, so the stars don't.
	i.star_thresholds = {
		"easy": [500, 1100, 2000],
		"standard": [500, 1100, 2000],
		"hard": [500, 1100, 2000],
	}
	i.options = [
		{"key": "steer", "label": "Steer", "choices": ["off", "on"], "labels": ["Off", "On"],
			"default": "off", "kind": "segmented"},
	]
	return i
