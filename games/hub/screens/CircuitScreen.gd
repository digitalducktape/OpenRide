class_name CircuitScreen
extends HubScreen
## A preset circuit's screen (spec §8.3): its lineup as role-coloured pills (as wide as each slot
## is long), the games in it, the total time, Difficulty, the best at that difficulty, and
## Start at the bottom right. (The custom builder and "My circuits" are plan phase D.)

const BODY_TOP := 190.0
const STRIP_H := 72.0
const INFO_SIZE := Vector2(HubTheme.W - 2 * HubTheme.MARGIN, 480)

var circuit: Dictionary = {}
var difficulty: Segmented
var start_button: Button
var _best_label: Label
var _stars: StarRow
var _difficulty := "standard"
var _waiting := false


func build() -> void:
	circuit = HubState.circuit(state, str(args.get("circuit_id", "")))
	_difficulty = HubPrefs.circuit_difficulty(rider_id, str(circuit.get("id", "")))
	top_bar("%d min circuit" % int(circuit.get("minutes", 0)))
	var col := VBoxContainer.new()
	col.name = "Body"
	col.position = Vector2(HubTheme.MARGIN, BODY_TOP)
	col.size = Vector2(HubTheme.W - 2 * HubTheme.MARGIN, HubTheme.H - BODY_TOP - 40)
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var slots: Array = circuit.get("slots", [])
	# Everything above Difficulty is still: one bake (one draw call instead of about 50).
	var info := VBoxContainer.new()
	info.name = "Info"
	info.add_theme_constant_override("separation", 22)
	var summary := HubTheme.label("%s · %d games · warm-up, work and recovery, then a cool-down" % [
		HubTheme.duration(int(circuit.get("total_sec", -1))), slots.size()], HudTheme.BODY, GameTheme.INK, false)
	info.add_child(summary)
	info.add_child(LineupStrip.new(slots, Vector2(HubTheme.W - 2 * HubTheme.MARGIN, STRIP_H), true))
	info.add_child(_legend(slots))
	info.add_child(_games(slots))
	info.add_child(_tiles(slots))
	col.add_child(HubCard.new(info, INFO_SIZE, queue, false))

	var bottom := HBoxContainer.new()
	bottom.name = "Bottom"
	bottom.add_theme_constant_override("separation", 40)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(bottom)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 18)
	left.alignment = BoxContainer.ALIGNMENT_END
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(left)
	left.add_child(HubTheme.heading("Difficulty"))
	difficulty = difficulty_picker(_difficulty)
	difficulty.changed.connect(func(d: String):
		_difficulty = d
		HubPrefs.set_circuit_difficulty(rider_id, str(circuit.get("id", "")), d)
		_show_best())
	left.add_child(difficulty)
	var best_row := HBoxContainer.new()
	best_row.add_theme_constant_override("separation", 14)
	left.add_child(best_row)
	_best_label = HubTheme.label("", HudTheme.BODY, GameTheme.TARGET)
	best_row.add_child(_best_label)
	_stars = StarRow.new(0, 40.0)
	_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_row.add_child(_stars)
	start_button = HubTheme.button("Start", _start, GameTheme.GO, HubTheme.START_SIZE)
	start_button.name = "Start"
	start_button.add_theme_font_size_override("font_size", HudTheme.MEDIUM)
	start_button.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(start_button)
	_show_best()


## The roles in the lineup, each a colour swatch with its name (never colour alone).
func _legend(slots: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	var roles: Array = []
	for s in slots:
		if str(s.role) not in roles:
			roles.append(str(s.role))
	for role in roles:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 12)
		var swatch := Panel.new()
		var st := StyleBoxFlat.new()
		st.bg_color = HudTheme.role_color(role)
		st.set_corner_radius_all(8)
		swatch.add_theme_stylebox_override("panel", st)
		swatch.custom_minimum_size = Vector2(44, 28)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(swatch)
		item.add_child(HubTheme.label(HudTheme.role_name(role), HudTheme.SMALL, GameTheme.MUTED))
		row.add_child(item)
	return row


## The games in the lineup as chips in their accents: "Tug of War ×2", on one line. A circuit
## drawn from a big pool (#75) has nine or ten games: the chips that don't fit become "+3 more".
func _games(slots: Array) -> Control:
	var counts := {}
	for s in slots:
		counts[str(s.game_id)] = int(counts.get(str(s.game_id), 0)) + 1
	var row := HBoxContainer.new()
	row.name = "Games"
	row.add_theme_constant_override("separation", CHIP_GAP)
	var chips: Array[Control] = []
	for id in counts:
		var info := GameRegistry.info(id)
		chips.append(_chip("%s ×%d" % [info.title if info else id, counts[id]], HubTheme.game_look(id).badge_style(null, true)))
	var used := 0.0
	var shown := 0
	for i in chips.size():
		var w := _chip_width(chips[i])
		var rest := chips.size() - i - 1
		# Room for this chip, and for a "+N more" after it unless it's the last.
		var more_w := 0.0
		if rest > 0:
			var probe := _more_chip(rest)
			more_w = _chip_width(probe) + CHIP_GAP
			probe.free()
		if used + w + more_w > INFO_SIZE.x:
			row.add_child(_more_chip(chips.size() - i))
			break
		row.add_child(chips[i])
		shown += 1
		used += w + CHIP_GAP
	for i in range(shown, chips.size()):
		chips[i].free()  # past the line: never in the tree
	return row


const CHIP_GAP := 18


## A chip's width before it is in the tree (its label's theme isn't resolved yet): the text in
## the display face, plus the style's margins and a little slack.
static func _chip_width(chip: Control) -> float:
	var label: Label = chip.get_child(0)
	var style: StyleBox = chip.get_theme_stylebox("panel")
	var text_w := GameTheme.display_font().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, HudTheme.SMALL).x
	return ceilf(text_w + style.get_minimum_size().x + 8.0)


func _chip(text: String, style: StyleBox) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", style)
	chip.add_child(HubTheme.label(text, HudTheme.SMALL, GameTheme.INK, true))
	return chip


## "+3 more": the games past the line, in the hub's own muted look.
func _more_chip(n: int) -> Control:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(GameTheme.MUTED, 0.35)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	return _chip("+%d more" % n, style)


## The circuit at a glance, as the summary's tiles: the total, the games, work and recovery.
func _tiles(slots: Array) -> Control:
	var by_role := {}
	for sl in slots:
		var role := str(sl.role)
		by_role[role] = int(by_role.get(role, 0)) + int(sl.duration_sec)
	var row := HBoxContainer.new()
	row.name = "Tiles"
	row.add_theme_constant_override("separation", int(HubTheme.GAP))
	row.add_child(_tile(HubTheme.duration(int(circuit.get("total_sec", -1))), "in all", GameTheme.INK))
	row.add_child(_tile("%d" % slots.size(), "games", GameTheme.INK))
	row.add_child(_tile(HudTheme.clock(float(by_role.get("work", 0))), "work", HudTheme.role_color("work")))
	row.add_child(_tile(HudTheme.clock(float(by_role.get("recovery", 0))), "recovery", HudTheme.role_color("recovery")))
	return row


func _tile(value: String, caption: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HubTheme.look().panel_style(null, 0.0, 22))
	panel.custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -6)
	panel.add_child(box)
	var v := HubTheme.label(value, HudTheme.BIG, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(v)
	var c := HubTheme.label(caption, HudTheme.SMALL, GameTheme.MUTED, true)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(c)
	return panel


func _show_best() -> void:
	var best := HubState.plan_best(state, str(circuit.get("id", "")), _difficulty)
	if best.is_empty():
		_best_label.text = "No best yet at this difficulty"
		_best_label.add_theme_color_override("font_color", GameTheme.MUTED)
		_stars.visible = false
	else:
		_best_label.text = "Your best: %d points, %d stars" % [best.score, best.stars]
		_best_label.add_theme_color_override("font_color", GameTheme.TARGET)
		_stars.visible = false


func refresh(hub_state: Dictionary) -> void:
	state = hub_state
	_show_best()


func request() -> Dictionary:
	return {"kind": "circuit", "preset_id": str(circuit.get("id", "")), "difficulty": _difficulty}


func _start() -> void:
	if _waiting:
		return
	_waiting = true
	start_button.disabled = true
	start_button.text = "Starting…"
	start.emit(request())


func start_answered() -> void:
	_waiting = false
	start_button.disabled = false
	start_button.text = "Start"
