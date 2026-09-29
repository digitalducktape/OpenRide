extends Control
## The idle scene: what shows before a session's first game loads and behind the summary.
## `Session` (its SessionDirector) swaps each segment's game in as the current scene and comes
## back here when the session ends (docs/GAMES.md, "The framework").


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.13)
	bg.size = Vector2(HudTheme.W, HudTheme.H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var title := HudTheme.label("OpenRide games", HudTheme.BIG)
	title.position = Vector2(0, HudTheme.H / 2 - 120)
	title.size = Vector2(HudTheme.W, 120)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var mode := HudTheme.label(
		"keyboard simulator" if InputBus.is_simulated() else "waiting for the session",
		HudTheme.BODY, HudTheme.MUTED)
	mode.position = Vector2(0, HudTheme.H / 2 + 20)
	mode.size = Vector2(HudTheme.W, 60)
	mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(mode)
	print("OPENRIDE_GAMES main ready renderer=%s adapter=%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
