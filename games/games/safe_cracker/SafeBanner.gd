class_name SafeBanner
extends CanvasLayer
## Safe Cracker's callouts (#41), centred just under the HUD's top bar and above the safe, so
## they never cover the dial (the HUD's centre message would sit on its reading):
##
##   ALARM: EASE OFF     a red badge that breathes while the alarm holds
##   CRACKED! +1150      a gold hero that slams in and fades
##
## One slot, laid out by containers: a full-rect MarginContainer with a top margin, its children
## centred across the top. Under the HUD (layer 10), so the HUD's panels and buttons stay on top;
## a child of the game, so it pauses with it. The alarm wins the slot over a crack.

const LAYER := 6
## The slot's top (1920x1080 canvas): under the status widget (its bottom is about y 150) and
## clear of the target plate above the door (its top is y 265).
const TOP := 158.0
const HERO_SIZE := 76

var alarm_badge: PanelContainer
var alarm_label: Label
var hero: Label
var _slot: MarginContainer
var _alarm_on := false
var _hero_tween: Tween
var _status: Control


func _init(look: GameTheme) -> void:
	layer = LAYER
	_slot = MarginContainer.new()
	_slot.name = "BannerSlot"
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot.add_theme_constant_override("margin_top", int(TOP))
	add_child(_slot)
	alarm_badge = PanelContainer.new()
	alarm_badge.name = "Alarm"
	alarm_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alarm_badge.add_theme_stylebox_override("panel", look.badge_style(Color(GameTheme.BAD, 0.96)))
	alarm_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	alarm_badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	alarm_badge.visible = false
	alarm_label = look.label("ALARM: EASE OFF", HudTheme.MEDIUM, GameTheme.INK, true)
	alarm_badge.add_child(alarm_label)
	_slot.add_child(alarm_badge)
	hero = look.hero("", HERO_SIZE, GameTheme.GOLD_GRADIENT, true)
	hero.name = "Hero"
	hero.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hero.visible = false
	_slot.add_child(hero)



## Keeps the slot under `status` (the game's widget on `hud`) from now on: a circuit's progress
## strip pushes the status area down, and the slot goes with it (as `CalloutBanner.follow`).
func follow(hud: Hud, status: Control) -> void:
	_status = status
	status.resized.connect(fit)
	hud.top_bar_moved.connect(fit)
	fit()


func fit() -> void:
	if is_instance_valid(_status):
		_slot.add_theme_constant_override("margin_top", int(ceilf(slot_top(_status.get_global_rect().end.y))))


## The slot's top for a status area ending at `status_bottom`.
static func slot_top(status_bottom: float) -> float:
	return maxf(TOP, status_bottom + CalloutBanner.STATUS_GAP)


## Shows the alarm badge (slammed in, then breathing) or takes it away.
func set_alarm(on: bool) -> void:
	if on == _alarm_on:
		return
	_alarm_on = on
	if on:
		_hide_hero()
		GameTheme.stop(alarm_badge, "fade")  # a fade-out still running
		alarm_badge.visible = true
		GameTheme.slam(alarm_badge).finished.connect(func():
			if _alarm_on:
				GameTheme.pulse(alarm_badge, true, 1.08, 0.8))
	else:
		GameTheme.pulse(alarm_badge, false)
		GameTheme.fade(alarm_badge, false).finished.connect(func():
			alarm_badge.modulate.a = 1.0)


func is_alarm_showing() -> bool:
	return _alarm_on


## Slams `text` in as the gold hero, holds it for `seconds` and fades it out.
func show_hero(text: String, seconds: float) -> void:
	if _alarm_on:
		return
	hero.text = text
	GameTheme.stop(hero, "fade")
	hero.visible = true
	if _hero_tween and _hero_tween.is_valid():
		_hero_tween.kill()
	GameTheme.slam(hero, 1.8, 0.4)
	_hero_tween = hero.create_tween()
	_hero_tween.tween_interval(maxf(seconds - GameTheme.FADE_SEC, 0.4))
	_hero_tween.tween_callback(func(): GameTheme.fade(hero, false))


func _hide_hero() -> void:
	if _hero_tween and _hero_tween.is_valid():
		_hero_tween.kill()
	GameTheme.stop(hero, "fade")
	hero.visible = false
